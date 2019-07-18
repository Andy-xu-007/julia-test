using PyCall
@pyimport os
@pyimport os.path as opa
@pyimport shutil
@pyimport pdfminer.pdfparser as pdfminer_parser
@pyimport pdfminer.pdfdocument as pdf_doc
@pyimport PyPDF2.pdf as py2pdf
@pyimport pdfminer.pdfinterp as pdf_interp
@pyimport pdfminer.layout as pdf_layout
@pyimport pdfminer.converter as pdf_conver
@pyimport pdfminer.pdfpage as pdf_page
@pyimport builtins

function PDF_parser()
    # input_RM_name = readline(stdin)  # 从输入读取多个字符或字符序列
    input_RM_name = "MKE06P80M48SF0RM_"
    pdf_name = string(input_RM_name, ".pdf")
    NXP_pdf = builtins.open(pdf_name, "rb")

    # using PDFminer to obtaining the content of document
    # Create a PDFparser object associated with the file object
    parser_pdf = pdfminer_parser.PDFParser(NXP_pdf)

    # using PyPDF to getting page number
    pypdf2_pdf = py2pdf.PdfFileReader(NXP_pdf)
    pagecount = pypdf2_pdf[:getNumPages]()

    # Create a PDF document object that store the document structure .
    doc = pdf_doc.PDFDocument(parser_pdf,password="")

    #  Link the parser and document object .
    parser_pdf[:set_document](doc)

    # Check if the document allows text extraction . if not . abort .
    if !doc[:is_extractable]
        # 以后会用自定义异常来抛出错误
        error("PDF text extraction not allowed")
    else
        # Create a PDF resource manager object that stores shared resources .
        resource = pdf_interp.PDFResourceManager()
        # Set parameters for analysis
        laparam = pdf_layout.LAParams()
        # Create a PDF page aggregator object
        device = pdf_conver.PDFPageAggregator(resource, laparams=laparam)
        # Create PDF interpreter object .
        interpreter = pdf_interp.PDFPageInterpreter(resource, device)

        # Process each page contained in the document
        gets_pages = pdf_page.PDFPage[:create_pages](doc)
        cat_2_4 = r"^.*?2\.4\s?(GH|gh)z.*?\.{2,}\s?\d+\n$"

        function kinetis_iMX()
            page_number::Int64 = 0
            page_line = ""
            for page ∈ gets_pages
                switch_par::Int64 = 1
                # Receive the LTpage object for the page
                interpreter[:process_page](page)
                # Use aggregator to fetch content
                layout = device[:get_result]()

                # 这里layout是一个LTPage对象 里面存放着 这个page解析出的各种对象 一般包括LTTextBox,
                # LTFigure, LTImage, LTTextBoxHorizontal 等等 想要获取文本就获得对象的text属性
                page_number += 1
                for out = layout
                    if builtins.hasattr(out,"get_text") && page_number > 2
                        out_text = out[:get_text]()
                        if occursin("Section number", out_text)
                            switch_par = 0
                        elseif switch_par == 0
                            # 特殊处理
                            if occursin("Reference Manual", out_text)
                                continue
                            elseif occursin(cat_2_4, out_text)
                                page_line = page_line * replace(out_text,"2.4 GHz" => "2_4 GHz")
                            else
                                page_line = page_line * out_text
                            end
                        end
                    end
                end
                if page_number > 5 && switch_par == 1
                    return page_line, page_number
                end
            end
        end
        content_sum = kinetis_iMX()
        interpreter[:process_page](builtins.next(gets_pages))
        # Y 轴坐标
        # println(builtins.dir(device[:get_result]()))
        current_page_coor_y = device[:get_result]()[:bbox][4]
        # 函数执行完的页数，由于需要提取页的Y轴长度，因此多加一页
        start_number = content_sum[2] + 1
        content_sum = split(content_sum[1], '\n', keepempty = false)
        return content_sum, pagecount, current_page_coor_y, gets_pages
    end
end

function catalogue_trim(content_sum)
    line_tidy = r"^\d+(\.\d+)+$" # 纯数字行判断
    line_str = r"^[^\.]{3}.*?\.{2,}\s?\d+$" # 没有数字序号开头的页码行
    line_num = r"^\d+\.\d+$" # 纯数字行，只有一级
    line_fragmentary = r"^\d+(\.\d+)+\s*.{2,}?\D$" # 没有目录点和页码的行
    line_str_R = r"^[^\.]{3}.{3,}?\D$" # 完整目录行的前面部分确实项
    line_str_r = r"^[^\.]{3}.{3,}?\d{2}$" # 缺少目录点的目录，但确实为目录行，很少见
    line_str_RR = r"^.{2,}?\.{2,}\s?\d+$" # 完整的或残缺的目录行，带目录点
    line_tidy_r = r"^\d+(\.\d+)+.*$" # 有数字开头的目录行，不一定是完整的
    line_end = r"^.{10,}?\d{2,}$" # 残缺目录行，后面有页码
    line_fragmentary_r = r"^\d+(\.\d+)+.{3,}?\d$" # 伪目录行，没有目录点，需要和后面的行累加
    line_cp = r"^[^\.]{3}.*\D$" # 非目录行
    CP_num = 'S'  # 提取章节序号
    # 目录整理
    for line = 2 : length(content_sum)-2
        fix_value = content_sum[line]
        if occursin("hapter", fix_value)
            CP_num = split(fix_value,' ')[end]
            # 有部分目录行，Chapter行和章节名颠倒，需要调换顺序
            chap_next = content_sum[line+1]
            if '.' in (chap_next * "rr")[1:4] || occursin("..", chap_next) || (occursin("NXP S", chap_next) && '.' ∉ content_sum[line - 1] )
                content_sum[line], content_sum[line - 1] = content_sum[line - 1], fix_value
            end
        # 出现纯数字行
        elseif fix_value != "00"
            n = line + 1
            line_n = content_sum[n]
            # 目录行是数字
            if occursin(line_tidy, fix_value)
                # 该目录下的子目录项与目录是同一章
                if CP_num == match(r"(\d+)", fix_value)[1] # 提取章节号
                    # 目前行是数字，下一行是完整目录
                    if occursin(line_str, line_n)
                        content_sum[line] = string(fix_value, ' ', line_n)
                        content_sum[n] = "00"
                    # 目前行是数字，下一目录行缺少目录点，仍然是目录行，下下行是数字
                    elseif occursin(line_tidy_r, content_sum[n+1]) && occursin(line_str_r, line_n)
                        content_sum[line] = fix_value * ' ' * content_sum[n]
                        content_sum[n] = "00"
                    # 目前行是数字，下一目录行缺少目录点，任然是目录行，下下行是页的结尾
                    elseif occursin(line_str_r, line_n) && ('.' ∉ content_sum[n + 1])
                        content_sum[line] = fix_value * ' ' * content_sum[n]
                        content_sum[n] = "00"
                    # 目前行和下一行不能满足
                    elseif !occursin(line_str_RR, line_n)
                        while !occursin(line_str_RR, content_sum[n])  # 数字 + 字母开头的目录行
                            n += 1
                        end
                        c_c = content_sum[n - 1]
                        cc = content_sum[n]
                        if occursin(line_tidy_r, cc)
                            content_sum[line] = fix_value * ' ' * c_c
                            content_sum[n - 1] = "00"
                        else
                            if occursin(line_str_R, c_c)
                                content_sum[line] = fix_value * ' ' * c_c * ' ' * content_sum[n]
                                content_sum[n - 1] = "00"
                                content_sum[n] = "00"
                            else
                                content_sum[line] = fix_value * ' ' * content_sum[n]
                                content_sum[n] = "00"
                            end
                        end
                    # 特殊的目录行
                    else
                        content_sum[line] = fix_value * ' ' * content_sum[n]
                        content_sum[n] = "00"
                    end
                # 该目录下的子目录项与目录不是同一章
                elseif parse(Int, match(r"(\d+)", fix_value)[1]) > parse(Int, CP_num)
                    # 找到与当前序号对应的章节
                    while !occursin("hapter", content_sum[n]) || split(content_sum[n],' ', keepempty = false)[end] != split(fix_value,'.')[1]
                        n += 1
                    end
                    while !occursin(line_str, content_sum[n]) || content_sum[n] == "00"
                        n += 1
                    end
                    c_c = content_sum[n-1]
                    if n-line>1 && '.'∉ c_c && c_c != "00"
                        content_sum[line] = fix_value * ' ' * c_c * content_sum[n]
                        content_sum[n - 1] = "00"
                        content_sum[n] = "00"
                    else
                        content_sum[line] = fix_value * ' ' * content_sum[n]
                        content_sum[n] = "00"
                    end
                end
            # 没有号的残缺目录行
            elseif occursin(line_str, fix_value)
                fix_value_1 = content_sum[line-1]
                if occursin(line_fragmentary, fix_value_1)
                    content_sum[line - 1] = fix_value_1 * ' ' + fix_value
                    content_sum[line] = "00"
                else
                    while !occursin(line_tidy, content_sum[n])
                        n += 1
                    end
                    content_sum[line] = content_sum[n] * ' ' * fix_value
                    content_sum[n] = "00"
                end
            # 没有目录点和页码的行
            elseif occursin(line_fragmentary, fix_value)
                if occursin(line_end, line_n)
                    content_sum[line] = fix_value * ' ' * line_n
                    content_sum[n] = "00"
                else
                    while !occursin(line_end, content_sum[n])
                        content_sum[line] = content_sum[line] * ' ' * content_sum[n]
                        content_sum[n] = "00"
                        n += 1
                    end
                    content_sum[line] = content_sum[line] * ' ' * content_sum[n]
                    content_sum[n] = "00"
                end
            # 伪目录行，需要和下面的行相加
            elseif occursin(line_fragmentary_r, fix_value)
                cc = content_sum[n + 1]
                if occursin(line_tidy_r, line_n)
                    continue
                elseif occursin(line_end, line_n)
                    content_sum[line] = fix_value * ' ' * line_n
                    content_sum[n] = "00"
                elseif occursin(line_end, cc)
                    content_sum[line] = *(fix_value, ' ', line_n, ' ', cc)
                    content_sum[n], content_sum[n + 1] = "00", "00"
                end
            end
        end
    end
    return filter(p -> p != "00", content_sum)
end

function module_extract(content_sum, pagecount)
    # 目录行中模块名的提取
    re_module_filter = r".*\((.*)\)"
    # 开头是数字的带寄存器的一级子目录的完整章节
    re_line_filter_re = r"^\d+\.\d+\s+.+?(egister|emory map).*?\.{2,}\s?\d+$"
    # 开头是数字的带寄存器的二级子目录的完整章节
    re_line_filter_sub = r"^\d+\.\d+\.\d+\s+.+?(egister|emory map).*?\.{2,}\s?\d+$"
    # 开头是数字的一级目录完整章节
    re_line_filter_first = r"\d+\.\d+\s+.+?\d+$"
    # 开头是数字的一级、二级目录完整章节
    re_line_filter_full = r"\d+\.\d+(\.\d+)?\s+.+?\d+$"
    # 任意目录完整行的匹配
    re_line_full = r"\d+(\.\d+)+\s.*?\d+$"

    chapter_num::Int64, temporary::Int64 = 3, 3  # 从目录的第n章开始检索
    module_A = Array{String,1}()
    module_list = Dict{String,Array}()  # 模块于页码范围组成的字典
    x::Int64 = 5
    line_end = true
    fix_line::Int64 = 0  # first register chunk for module
    page_store = Array{String,1}()  # 存储每一页的一级和二级目录
    end_number::Int64 = 20000  # 初始化页数
    for content_line = 1:length(content_sum)
        # 提取最后一个带有...的目录行
        if line_end && occursin(re_line_full, content_sum[end-content_line])
            end_number = pagecount - content_line
            line_end = false
        end
        for ii in 2:4
            println(ii)
        end
        fix_value = content_sum[content_line]
        # 提取每一章寄存器的相关章节
        if !isempty(module_A)
            if temporary == chapter_num
                # 一章中只含有一个寄存器（一级目录），基本上是这种情况，所以不和下面的条件放到一起，保持模块名字的简洁一致
                if x == 0 && occursin(re_line_filter_re, fix_value)
                    push!(module_list[module_A[end]], split(fix_value, r"\.+\s*", keepempty = false)[end])
                    n = content_line + 1
                    while !occursin(re_line_filter_first, content_sum[n]) && n < end_number
                        n += 1
                    end
                    push!(module_list[module_A[end]], split(content_sum[n], r"\.+\s*", keepempty = false)[end])
                    x = 1
                    fix_line = 1
                # 一章中含有两个寄存器（一级目录），比较少
                elseif x == 1 && occursin(re_line_filter_re, fix_value)
                    fix_line += 1
                    m_key_se = *(module_A[end], '_', "O0", "$fix_line")
                    module_A[end] = m_key_se
                    module_list[m_key_se] = [split(fix_value, r"\.+\s*")[end]]
                    n = content_line + 1
                    while !occursin(re_line_filter_first, content_sum[n]) && n < end_number
                        n += 1
                    end
                    push!(module_list[m_key_se], split(content_sum[n], r"\.+\s*")[end])
                end
                occursin(re_line_filter_full, fix_value) && push!(page_store, fix_value)
            else
                temporary += 1
                module_list[module_A[end]] = []
            end
        end
        # 提取目录中每一章的模块
        if occursin("hapter " * "$chapter_num", fix_value)
            if x == 0 && isempty(module_list[module_A[end]])  # 删除没有寄存器的章节
                pop!(module_list)
                pop!(module_A)
            end
            !occursin("..", content_sum[content_line + 1]) ? fix_value_1 = content_sum[content_line + 1] : fix_value_1 = content_sum[content_line - 1]
            '(' ∈ fix_value_1 ? push!(module_A, match(re_module_filter, fix_value_1).captures[1]) : push!(module_A, fix_value_1)
            chapter_num += 1
            # 如果上一个一级目录没有寄存器，则对二级目录判定，这种情况极少
            if !isempty(page_store) && (x == 0)
                bb:Int64 = 0
                println(typeof(page_store))
                println(length(page_store))
                for ii = 2:10
                    println("ii = ", ii)
                    # 在上一个模块内检索二级目录含寄存器的
                    if occursin(re_line_filter_sub, page_store[ii])
                        bb += 1
                        m_key_se = module_A[end-1] * '_' * "0O" * "$bb"
                        module_A[end-1] = m_key_se
                        module_list[m_key_se] = [split(page_store[ii], r"\.+\s*", keepempty = false)[end],]
                        n = ii + 1
                        # 在上一个模块内检索二级目录含寄存器的截至页
                        if n < length(page_store) -1
                            while !occursin(re_line_filter_full, page_store[n]) && n <= length(page_store)-1
                                n += 1
                            end
                        end
                        # 上一个模块内最后一个模块没有截至页，因为无法判断最后一页，所以选择到下一个模块的一二级目录的开始
                        if n > length(page_store) - 1
                            n = content_line + 1
                            while !occursin(re_line_filter_full, content_sum[n]) && n < end_number
                                n += 1
                            end
                            push!(module_list[m_key_se], split(content_sum[n], r"\.+\s*")[end])
                        else
                            push!(module_list[m_key_se], split(page_store[n], r"\.+\s*")[end])
                        end
                    end
                end
            end
            page_store = Array{String,1}()
            x = 0
        end
    end
    return module_A, module_list
end

function main()
    content_sum, pagecount, _current_page_coor_y, gets_pages = PDF_parser()
    current_page_coor_y = _current_page_coor_y
    content_sum = catalogue_trim(content_sum)
    module_extract(content_sum, pagecount)
    # module_A, module_list = module_extract(content_sum, pagecount)
    # println(module_A)
    # println(keys(module_list))

end

main()
#
#
# function creat_folder()
#     if opa.isdir("test")
#         ss = string(pwd(), "\\", "test") # pwd() 获取当前工作目录
#         shutil.rmtree(ss)
#     end
#     mkpath("test")
#     ss = pwd() * "\\" * "test"
#     test_info = ss * "\\" * "test_info.text"
#     test_module = ss * "\\" * "module.html"
#     test_bit = ss * "\\" * "bit.html"
#
#     # using Pandas
#     # Pandas.set_option("max_colwidth", 400)
#     # 输入路径+手册名，不包含后缀
# end
