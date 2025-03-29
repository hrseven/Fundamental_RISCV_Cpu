/*
ֱ��ӳ��Cache
- Cache������8��
- ���С��4�֣�16�ֽ� 128λ��
- ����д��д�������
*/
module cache_2_fifo #(
    parameter INDEX_WIDTH       = 3,    // Cache����λ�� 2^3=8��
    parameter LINE_OFFSET_WIDTH = 2,    // ��ƫ��λ��������һ�еĿ�� 2^2=4��
    parameter SPACE_OFFSET      = 2,    // һ����ַ�ռ�ռ1���ֽڣ����һ������Ҫ4����ַ�ռ䣬���ڼ���Ϊ���ֶ�ȡ�������ַ��ʱ�����Ĭ�Ϻ���λΪ0
    parameter WAY_NUM           = 2,     // Cache N·������(N=1��ʱ����ֱ��ӳ��)
    parameter USED_WIDTH        = 1
)(
    input                     clk,    
    input                     rstn,
    /* CPU�ӿ� */  
    input [31:0]              addr,   // CPU��ַ
    input                     r_req,  // CPU������
    input                     w_req,  // CPUд����
    input [31:0]              w_data,  // CPUд����
    output reg[31:0]          r_data,  // CPU������
    output reg                miss,   // ����δ����
    /* �ڴ�ӿ� */  
    output reg                     mem_r,  // �ڴ������
    output reg                     mem_w,  // �ڴ�д����
    output reg [31:0]              mem_addr,  // �ڴ��ַ
    output reg [127:0] mem_w_data,  // �ڴ�д���� һ��дһ��
    input      [127:0] mem_r_data,  // �ڴ������ һ�ζ�һ��
    input                          mem_ready  // �ڴ�����ź�
);

    // Cache����
    localparam
        // Cache�п��
        LINE_WIDTH = 32 << LINE_OFFSET_WIDTH,
        // ���λ���
        TAG_WIDTH = 32 - INDEX_WIDTH - LINE_OFFSET_WIDTH - SPACE_OFFSET,
        // Cache����
        SET_NUM   = 1 << INDEX_WIDTH;
    
    // Cache��ؼĴ���
    reg [31:0]           addr_buf;    // �����ַ����-���ڱ���CPU�����ַ
    reg [31:0]           w_data_buf;  // д���ݻ���
    reg op_buf;  // ��д�������棬������MISS״̬���ж��Ƕ�����д�������д����Ҫ������д���ڴ� 0:�� 1:д
    reg [LINE_WIDTH-1:0] ret_buf;     // �������ݻ���-���ڱ����ڴ淵������

    // Cache����
    wire [INDEX_WIDTH-1:0] r_index;  // ��������ַ
    wire [INDEX_WIDTH-1:0] w_index;  // ����д��ַ
    wire [LINE_WIDTH-1:0]  r_line_0,r_line_1;   // Data Bram������
    reg [LINE_WIDTH-1:0] r_line;
    wire [LINE_WIDTH-1:0]  w_line_0,w_line_1;   // Data Bramд����
    wire [LINE_WIDTH-1:0] w_line;
    wire [LINE_WIDTH-1:0]  w_line_mask;  // Data Bramд��������
    wire [LINE_WIDTH-1:0]  w_data_line;  // ����д������λ�������
    wire [TAG_WIDTH-1:0]   tag;      // CPU�����ַ�з���ı�� ���ڱȽ� Ҳ������д��
    wire [TAG_WIDTH-1:0]   r_tag_0,r_tag_1;    // Tag Bram������ ���ڱȽ�
    wire [LINE_OFFSET_WIDTH-1:0] word_offset;  // ��ƫ��
    reg  [31:0]            cache_data_0,cache_data_1;  // Cache����
    reg  [31:0]            mem_data;    // �ڴ�����
    reg [31:0]            dirty_mem_addr; // ͨ��������tag�Ͷ�Ӧ��index��ƫ�Ƶȵõ�����Ӧ���ڴ��ַ��д�ص���ȷ��λ��
    wire valid_0,valid_1,valid;  // Cache��Чλ
    wire dirty_0,dirty_1;
    reg dirty;  // Cache��λ.
    wire use_0,use_1;
    reg used_0,used_1;
    reg  w_valid_0,w_valid_1;  // Cacheд��Чλ
    reg  w_dirty_0,w_dirty_1;  // Cacheд��λ
    wire hit_0,hit_1;    // Cache����

    // Cache��ؿ����ź�
    reg addr_buf_we;  // �����ַ����дʹ��
    reg ret_buf_we;   // �������ݻ���дʹ��
    reg data_we_0,data_we_1;      // Cacheдʹ��
    reg tag_we_0,tag_we_1;       // Cache���дʹ��
    reg data_from_mem;  // ���ڴ��ȡ����
    reg refill;       // �����Ҫ������䣬��MISS״̬�½��ܵ��ڴ����ݺ���1,��IDLE״̬�½���������0
    reg choose;

    // ״̬���ź�
    localparam 
        IDLE      = 3'd0,  // ����״̬
        READ      = 3'd1,  // ��״̬
        MISS      = 3'd2,  // ȱʧʱ�ȴ���������¿�
        WRITE     = 3'd3,  // д״̬
        W_DIRTY   = 3'd4;  // дȱʧʱ�ȴ�����д�����
    reg [2:0] CS;  // ״̬����ǰ״̬
    reg [2:0] NS;  // ״̬����һ״̬

    // ״̬��
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            CS <= IDLE;
        end else begin
            CS <= NS;
        end
    end

    // �м�Ĵ���������ʼ�������ַ��д���ݣ��������Ϊaddr_buf�еĵ�ַΪ��ǰCache���ڴ���������ַ����addr�еĵ�ַΪ�µ������ַ
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            addr_buf <= 0;
            ret_buf <= 0;
            w_data_buf <= 0;
            op_buf <= 0;
            refill <= 0;
        end else begin
            if (addr_buf_we) begin
                addr_buf <= addr;
                w_data_buf <= w_data;
                op_buf <= w_req;
            end
            if (ret_buf_we) begin
                ret_buf <= mem_r_data;
            end
            if (CS == MISS && mem_ready) begin
                refill <= 1;
            end
            if (CS == IDLE) begin
                refill <= 0;
            end
        end
    end

    // �������ַ���н���
    assign r_index = addr[INDEX_WIDTH+LINE_OFFSET_WIDTH+SPACE_OFFSET - 1: LINE_OFFSET_WIDTH+SPACE_OFFSET];
    assign w_index = addr_buf[INDEX_WIDTH+LINE_OFFSET_WIDTH+SPACE_OFFSET - 1: LINE_OFFSET_WIDTH+SPACE_OFFSET];
    assign tag = addr_buf[31:INDEX_WIDTH+LINE_OFFSET_WIDTH+SPACE_OFFSET];
    assign word_offset = addr_buf[LINE_OFFSET_WIDTH+SPACE_OFFSET-1:SPACE_OFFSET];

    // ����ַ����
    always@(*)begin
        if(!used_0)begin
            dirty_mem_addr ={r_tag_0, w_index}<<(LINE_OFFSET_WIDTH+SPACE_OFFSET);
        end
        else if(!used_1)begin
            dirty_mem_addr ={r_tag_1, w_index}<<(LINE_OFFSET_WIDTH+SPACE_OFFSET);
        end
    end

    // д�ص�ַ�����ݼĴ���
    reg [31:0] dirty_mem_addr_buf;
    reg [127:0] dirty_mem_data_buf;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dirty_mem_addr_buf <= 0;
            dirty_mem_data_buf <= 0;
        end else begin
            if (CS == READ || CS == WRITE) begin
                dirty_mem_addr_buf <= dirty_mem_addr;
                dirty_mem_data_buf <= r_line;
            end
        end
    end

    // Tag Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 3) // ���λΪ��Чλ���θ�λΪ��λ����λΪ���λ,plus���ʹ��λ
    ) tag_bram_0(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({used_0,w_valid_0, w_dirty_0, tag}),
        .we(tag_we_0),
        .dout({use_0,valid_0, dirty_0, r_tag_0})
    );
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 3) // ���λΪ��Чλ���θ�λΪ��λ����λΪ���λ��,plus���ʹ��λ
    ) tag_bram_1(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({used_1,w_valid_1, w_dirty_1, tag}),
        .we(tag_we_1),
        .dout({use_1,valid_1, dirty_1, r_tag_1})
    );
    always@(posedge clk)begin
        if(CS==IDLE)begin
            if(w_req)begin
                if(!used_0)begin
                        used_0<=1;
                        used_1<=0;
                end
                else begin
                    used_0<=0;
                    used_1<=1;
                end
            end
            else if(r_req)begin
                if(!hit_0&&!hit_1)begin
                    if(!used_0)begin
                        used_0<=1;
                        used_1<=0;
                    end
                    else begin
                        used_0<=0;
                        used_1<=1;
                    end
                end
            end
        end
    end
    // Data Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram_0(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we_0),
        .dout(r_line_0)
    );

    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram_1(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we_1),
        .dout(r_line_1)
    );

    // �ж�Cache�Ƿ�����
    assign hit_0= valid_0 && (r_tag_0 == tag);
    assign hit_1= valid_1 && (r_tag_1 == tag);

    // д��Cache ����Ҫ�ж������к�д�뻹��δ���к�д��
    assign w_line_mask = 32'hFFFFFFFF << (word_offset*32);   // д����������
    assign w_data_line = w_data_buf << (word_offset*32);     // д��������λ
    assign w_line = (CS == IDLE && op_buf) ? ret_buf & ~w_line_mask | w_data_line : // д��δ���У���Ҫ���ڴ�������д�����ݺϲ�
                    (CS == IDLE) ? ret_buf : // ��ȡδ����
                    r_line & ~w_line_mask | w_data_line; // д������,��Ҫ�Զ�ȡ��������д������ݽ��кϲ�

    // ѡ��������� ��Cache���ߴ��ڴ� �����ѡ�����д�С�йأ����������������ƫ��λ������Ҳ��Ҫ����
    always @(*) begin
        case (word_offset)
            0: begin
                cache_data_0 = r_line_0[31:0];
                cache_data_1 = r_line_1[31:0];
                mem_data = ret_buf[31:0];
            end
            1: begin
                cache_data_0 = r_line_0[63:32];
                cache_data_1 = r_line_1[63:32];
                mem_data = ret_buf[63:32];
            end
            2: begin
                cache_data_0 = r_line_0[95:64];
                cache_data_1 = r_line_1[95:64];
                mem_data = ret_buf[95:64];
            end
            3: begin
                cache_data_0 = r_line_0[127:96];
                cache_data_1 = r_line_1[127:96];
                mem_data = ret_buf[127:96];
            end
            default: begin
                cache_data_0 = 0;
                cache_data_1 = 0;
                mem_data = 0;
            end
        endcase
    end

    always@(*)begin
        if(data_from_mem)begin
            r_data=mem_data;
        end
        else begin
            if(hit_0)begin
                r_data=cache_data_0;
            end
            else if(hit_1)begin
                r_data=cache_data_1;
            end
            else begin
                r_data=0;
            end
        end
    end

    // ״̬�������߼�
    always @(*) begin
        case(CS)
            IDLE: begin
                if (r_req) begin
                    NS = READ;
                end else if (w_req) begin
                    NS = WRITE;
                end else begin
                    NS = IDLE;
                end
            end
            READ: begin
                if (miss&& !dirty) begin
                    NS = MISS;
                end else if (miss && dirty) begin
                    NS = W_DIRTY;
                end else if (r_req) begin
                    NS = READ;
                end else if (w_req) begin
                    NS = WRITE;
                end else begin
                    NS = IDLE;
                end
            end
            MISS: begin
                if (mem_ready) begin // ����ص�IDLE��ԭ����Ϊ���ӳ�һ���ڣ��ȴ�����������¿�д��Cache�еĶ�Ӧλ��
                    NS = IDLE;
                end else begin
                    NS = MISS;
                end
            end
            WRITE: begin
                if (miss && !dirty) begin
                    NS = MISS;
                end else if (miss && dirty) begin
                    NS = W_DIRTY;
                end else if (r_req) begin
                    NS = READ;
                end else if (w_req) begin
                    NS = WRITE;
                end else begin
                    NS = IDLE;
                end
            end
            W_DIRTY: begin
                if (mem_ready) begin  // д������ص�MISS״̬�ȴ���������¿�
                    NS = MISS;
                end else begin
                    NS = W_DIRTY;
                end
            end
            default: begin
                NS = IDLE;
            end
        endcase
    end

    // ״̬�������ź�
    always @(*) begin
        addr_buf_we   = 1'b0;
        ret_buf_we    = 1'b0;
        tag_we_0        = 1'b0;
        tag_we_1        = 1'b0;
        w_valid_0       = 1'b0;
        w_valid_1       = 1'b0;
        w_dirty_0       = 1'b0;
        w_dirty_1       = 1'b0;
        data_from_mem = 1'b0;
        miss          = 1'b0;
        mem_r         = 1'b0;
        mem_w         = 1'b0;
        mem_addr      = 32'b0;
        mem_w_data    = 0;
        case(CS)
            IDLE: begin
                addr_buf_we = 1'b1; // �����ַ����дʹ��
                miss = 1'b0;
                ret_buf_we = 1'b0;
                if(refill) begin
                    data_from_mem = 1'b1;
                    if(!choose)begin
                        w_valid_0 = 1'b1;
                        w_dirty_0 = 1'b0;
                        data_we_0 = 1'b1;
                        tag_we_0 = 1'b1;
                        if (op_buf) begin // д
                        w_dirty_0 = 1'b1;
                        end 
                    end
                    if(choose)begin
                        w_valid_1 = 1'b1;
                        w_dirty_1 = 1'b0;
                        data_we_1 = 1'b1;
                        tag_we_1 = 1'b1;
                        if (op_buf) begin // д
                        w_dirty_1 = 1'b1;
                        end 
                    end
                end
                else begin
                    data_we_0=0;
                    data_we_1=0;
                end
            end
            READ: begin
                data_from_mem = 1'b0;
                data_we_0=0;
                data_we_1=0;
                if (hit_0||hit_1) begin // ����
                    miss = 1'b0;
                    addr_buf_we = 1'b1; // �����ַ����дʹ��
                    if(hit_0)begin
                        r_line=r_line_0;
                    end
                    if(hit_1)begin
                        r_line=r_line_1;
                    end
                end else begin // δ����
                    miss = 1'b1;
                    addr_buf_we = 1'b0; 
                    used_0=use_0;
                    used_1=use_1;
                    dirty=(!used_0)?dirty_0:dirty_1;
                    r_line=(!used_0)?r_line_0:r_line_1;
                    if(!used_0)begin
                        choose=0;
                    end
                    else begin
                        choose=1;
                    end
                    if (dirty) begin // ��������Ҫд��
                        mem_w = 1'b1;
                        mem_addr = dirty_mem_addr;
                        mem_w_data = r_line; // д������
                    end
                end
            end
            MISS: begin
                miss = 1'b1;
                mem_r = 1'b1;
                data_we_0=0;
                data_we_1=0;
                mem_addr = addr_buf;
                if (mem_ready) begin
                    mem_r = 1'b0;
                    ret_buf_we = 1'b1;
                end 
            end
            WRITE: begin
                data_from_mem = 1'b0;
                data_we_0=0;
                data_we_1=0;
                if (hit_0) begin // ����
                    miss = 1'b0;
                    addr_buf_we = 1'b1; // �����ַ����дʹ��
                    w_valid_0 = 1'b1;
                    w_dirty_0 = 1'b1;
                    data_we_0 = 1'b1;
                    tag_we_0 = 1'b1;
                    r_line=r_line_0;
                end 
                else if(hit_1)begin
                    miss = 1'b0;
                    addr_buf_we = 1'b1; // �����ַ����дʹ��
                    w_valid_1 = 1'b1;
                    w_dirty_1 = 1'b1;
                    data_we_1 = 1'b1;
                    tag_we_1 = 1'b1;
                    r_line=r_line_1;
                end
                else begin // δ����
                    miss = 1'b1;
                    addr_buf_we = 1'b0; 
                    used_0=use_0;
                    used_1=use_1;
                    dirty=(!used_0)?dirty_0:dirty_1;
                    r_line=(!used_0)?r_line_0:r_line_1;

                    if (dirty) begin // ��������Ҫд��
                        mem_w = 1'b1;
                        mem_addr = dirty_mem_addr;
                        mem_w_data = r_line; // д������
                    end
                end
            end
            
            W_DIRTY: begin
                miss = 1'b1;
                mem_w = 1'b1;
                data_we_0=0;
                data_we_1=0;
                mem_addr = dirty_mem_addr_buf;
                mem_w_data = dirty_mem_data_buf;
                if (mem_ready) begin
                    mem_w = 1'b0;
                end
            end
            default:;
        endcase
    end

endmodule