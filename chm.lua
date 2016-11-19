local source_doc_root=[[f:\BM\E66230_01\]]
local target_doc_root=[[f:\BM\newdoc12\]]
local errmsg_book=[[ERRMG]]
local plsql_package_ref='ARPLS'
--[[--FOR 11g
local source_doc_root='f:\\BM\\E11882_01\\'
local target_doc_root='f:\\BM\\newdoc11\\'
local errmsg_book='server.112\\e17766'
local plsql_package_ref='appdev.112\\e40758'
--]]

--[[
    (c)2016 by hyee, MIT license, https://github.com/hyee/Oracle-DB-Document-CHM-builder

    .hhc/.hhk/.hhp files are all created under the root path

    .hhc => Content rules(buildJson): target.json
    .hhk => Index rules(buildIdx):
        1. Common books => index.htm:
            dl -> <dd class='*ix'>content,<a href="link">...<a>
            div -> ul -> li -> [ul|a]
        2. Javadoc books(contains 'allclasses-frame.html') => index-all.html, index-files\index-[1-30].html:
            <a (href="*.html#<id>" | href="*.html" title=)>content</a>
        3. Glossary => glossary.htm
            <p class="glossterm">[content]<a (name=|id=)>[content]</a></p>
        4. Book Oracle Error messages(self.errmsg):
            dt -> <a (name=|id=)>
        5. Book PL/SQL Packages Reference(self.plsql_api):
            target.json -> level 1 and 3 -> First word in upper-case
    .hhp => Project rules(buildHhp):
        1. Include all files
        2. Enable options: Create binary TOC/Create binary indexes/Compile full-text search/show MSDN menu
    HTML file substitution rules(processHTML):
        1. For javadoc, only replace all &lt/gt/amp as >/</& in javascript due to running into errors
        2. For others:
            1). Remove all <script>/<a[href="#BEGIN"]>/<header>/<footer> elements, used customized header instead
            2). For all 'a' element, remove all 'onclick' and 'target' attributes
            3). For all links that point to the top 'index.htm', replace as 'MS-ITS:index.chm::/index.htm'
            4). For all links that point to other books:
                a. Replace '.htm?<parameters>' as '.htm'
                b. Caculate the <relative_path> based on the root path and replace '\' as '.', assign as the <file_name>
                c. Final address is 'MS-ITS:<file_name>.chm::/<relative_path>/<html_file(#...)?>'
    Book list rules: all directories that contains 'toc.htm'

--]]
local chm_builder=[[C:\Program Files (x86)\HTML Help Workshop\hhc.exe]]
local html=require("htmlparser")
local json=require("json")
local io,pairs,ipairs,math=io,pairs,ipairs,math

local reps={
    ["\""]="&quot;",
    ["<"]="&lt;",
    [">"]="&gt;"
}

local function rp(s) return reps[s] end
local function strip(str)
    return str:gsub("[\n\r\b]",""):gsub("^[ ,]*(.-)[ ,]*$", "%1"):gsub('<.->',''):gsub("  +"," "):gsub("[\"<>]",rp):gsub("%s*&reg;?%s*"," ")
end

local jcount={}
local builder={}
function builder.new(self,dir,build,copy)
    dir=dir:gsub('[\\/]+','\\'):gsub("\\$","")
    if dir:find(target_doc_root,1,true)==1 then dir=dir:sub(#target_doc_root+1) end
    local _,depth,parent,folder=dir:gsub('[\\/]','')
    depth=depth and depth+1 or 1
    if depth>1 then
        parent,folder=dir:match('^(.+)\\([^\\]+)$')
    else
        folder=dir
    end
    local full_dir=target_doc_root..dir..'\\'
    local o={
        ver=errmsg_book=='ERRMG' and '12c' or '11g',
        toc=full_dir..'toc.htm',
        json=full_dir..'target.json',
        idx=full_dir..'index.htm',
        hhc="",
        hhk="",
        depth=depth,
        root=target_doc_root,
        dir=dir,
        full_dir=full_dir,
        parent=parent,
        folder=folder,
        name=dir:gsub("[\\/]+",".")}
    if copy then
        local targetroot='"'..full_dir..'"'
        local sourceroot=source_doc_root..dir.."\\"
        local lst={"toc.htm","index.htm","title.htm"}
        for j=1,3 do self.exists(sourceroot..lst[j]) end
        local exec=io.popen("mkdir "..targetroot..' 2>nul & xcopy "'..sourceroot..'*" '..targetroot.." /E/Y/Q  /EXCLUDE:exclude.txt")
        exec:close()
    end
    if self.exists(full_dir.."title.htm",true) then 
        o.title="title.htm"
    else
        o.title="toc.htm"
    end

    if self.exists(full_dir..'allclasses-frame.html') then o.is_javadoc=true end
    setmetatable(o,self)
    self.__index=self
    if build then 
        o:startBuild()
    end
    return o
end

function builder.read(file)
    local f,err=io.open(file,'r')
    if not f then
        return nil,err
    else
        local text=f:read('*a')
        f:close()
        return text
    end
end

function builder.exists(file,silent)
    local text,err=builder.read(file)
    return text
end

function builder.save(path,text)
    if type(path)=="table" then
        print(debug.traceback())
    end
    local f=io.open(path,"w")
    f:write(text)
    f:close()
end

function builder:getContent(file)
    local txt=self.exists(file)
    if not txt then return end
    local title=txt:match([[<meta name="doctitle" content="([^"]+)"]])
    if not title then title=txt:match("<title>(.-)</title>") end
    if title then title=title:gsub("%s*&reg;?%s*"," "):gsub("([\1-\127\194-\244][\128-\193])", ''):gsub('%s*|+%s*',''):gsub('&.-;','') end
    local root=html.parse(txt):select("div[class^='IND']")
    return root and root[1] or nil,title
end

function builder:buildGlossary(tree)
    local text=self.read(self.full_dir..'glossary.htm')
    if not text then return end
    local nodes=html.parse(text):select('p[class="glossterm"]')
    for _,p in ipairs(nodes) do
        local a=p.nodes[1]
        local ref=a.attributes.id or a.attributes.name
        if a.name=="a" and ref then
            local content=a:getcontent():gsub('%s+$','')
            if content=="" then
                content=p:getcontent():gsub('<.->',''):gsub('%s+$','')
            end
            tree[#tree+1]={name=content,ref={'glossary.htm#'..ref}}
        end
    end
end

function builder:buildIdx()
    local hhk={[[<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><HEAD>
        <meta content="Microsoft HTML Help Workshop 4.1" name="GENERATOR">
        <!-- Sitemap 1.0 -->
      </HEAD>
      <BODY><UL>]]}

    local c=self:getContent(self.idx)
    if not c then c=self:getContent(self.idx..'l') end
    if not c and not self.errmsg and not self.is_javadoc then return end
    
    local function append(level,txt)
        hhk[#hhk+1]='\n    '..string.rep("  ",level).. txt
    end

    local tree={}
    if self.errmsg then 
        tree=self.errmsg
    elseif self.is_javadoc then --process java-doc api
        local text=self.read(self.full_dir..'index-all.html')
        if not text then
            local files={}
            for i=1,30 do
                files[#files+1]=self.read(self.full_dir..'index-files\\index-'..i..'.html')
            end
            text=table.concat(files,'')
            if text=='' then text=nil end
        end
        if text then
            local nodes=html.parse(text):select("a")
            local addrs={}
            self.hhk='index-all.html'
            for idx,a in ipairs(nodes) do
                if a.attributes.href and a.attributes.href:find('.htm',1,true) then
                    local content=a:getcontent():gsub('<.->',''):gsub('%s+$','')
                    local ref=a.attributes.href:gsub('^%.[\\/]?',''):gsub('/','\\')
                    if ((ref:find('#',1,true) or 0)> 2 or a.attributes.title) and content~="" and not addrs[content..ref] then
                        addrs[content..ref]=1
                        tree[#tree+1]={name=content,ref={ref}}
                    end
                end
            end
        end
    else
        local nodes=c:select("dd[class*='ix']")
        local treenode,plsql_api={},self.plsql_api or {}
        for _,node in ipairs(nodes) do
            local level=tonumber(node.attributes.class:match('l(%d+)ix'))
            if level then
                local n={name=node:getcontent():gsub('[%s,]*<.*','') ,ref={}}
                if n.name:find('<em>See</em>',1,true) then n.name=n.name:gsub('%.?%s*<em>.+','') end
                n.name=n.name:gsub('<.->','')
                local found=false
                for _,a in ipairs(node.nodes) do
                    if a.name=='a' then
                        if not found then found=true end
                        n.ref[#n.ref+1]=a.attributes.href
                    end
                end
                treenode[level]=n
                if level>1 then
                    table.insert(treenode[level-1],n)
                    for lv=1,level-1 do
                        if #treenode[lv].ref==0 then treenode[lv].ref=n.ref end
                    end
                else
                    tree[#tree+1],plsql_api[n.name]=n,nil
                end
            end
        end

        if #nodes==0 then
            local uls=c:select("div > ul")
            local function access_childs(li,level)
                if li.name~="li" or not li.nodes[1] then return end
                local n={name=li:getcontent():gsub('[%s,]+<.*$',''):gsub('^%s+',''),ref={}}
                if n.name=="" then return end
                if level==1 then 
                    tree[#tree+1],plsql_api[n.name]=n,nil
                elseif n.name=="about" then
                    level,n=level-1,treenode[level-1]
                else
                    table.insert(treenode[level-1],n)
                end
                treenode[level]=n
                
                local lis=li:select("li")
                if li.nodes[1].name~="ul" then
                    for _,a in ipairs(li:select("a")) do
                        n.ref[#n.ref+1]=a.attributes.href
                    end
                    for lv=1,level-1 do
                        if #treenode[lv].ref==0 then treenode[lv].ref=n.ref end
                    end
                else
                    for _,child in ipairs(li.nodes[1].nodes) do
                        access_childs(child,level+1)
                    end
                end
            end

            for _,ul in ipairs(uls) do
                for _,li in ipairs(ul.nodes) do
                    access_childs(li,1)
                end
            end
        end

        for _,n in pairs(plsql_api) do tree[#tree+1]=n end
        self:buildGlossary(tree)
    end

    local function travel(level,node,parent)
        if not parent then
            for i=1,#node do 
                travel(level,node[i],node) 
            end
            return
        end
        if node.name~="" then
            for i=1,#node.ref do
                append(level+1,"<LI><OBJECT type=\"text/sitemap\">")
                if node.name:find("^#SEE#")==1 then
                    node.name=node.name:sub(6)
                    append(level+2,([[<param name="Name"  value="%s">]]):format("See Also "..node.name))
                    append(level+2,([[<<param name="See Also" value="%s">]]):format(node.name))
                else
                    append(level+2,([[<param name="Name"  value="%s">]]):format(node.name))
                    append(level+2,([[<param name="Local" value="%s">]]):format(self.dir..'\\'..node.ref[i]))
                end
                if i==#node.ref and #node>0 then
                    append(level+1,'</OBJECT><UL>')
                    for i=1,#node do travel(level+1,node[i],node) end
                    append(level+1,'</UL></LI>')
                else
                    append(level,'</OBJECT></LI>')
                end
            end
        end
    end
    travel(0,tree)
    append(0,"</UL></BODY></HTML>")
    self.hhk=self.name..".hhk"
    self.save(self.root..self.hhk,table.concat(hhk))
end

function builder:buildJson()
    self.hhc=self.name..".hhc"
    local hhc={
    [[<HTML><HEAD>
        <meta content="Microsoft HTML Help Workshop 4.1" name="GENERATOR">
        <!-- Sitemap 1.0 -->
      </HEAD>
      <BODY>
        <OBJECT type="text/site properties">
          <param name="Window Styles" value="0x800225">
          <param name="comment" value="title:Online Help">
          <param name="comment" value="base:toc.htm">
        </OBJECT><UL>]]}
    local function append(level,txt)
        hhc[#hhc+1]='\n    '..string.rep("  ",level*2).. txt
    end

    local txt=self.read(self.json)
    if not txt then
        local title,href
        if self.toc:lower():find('\\nav\\') then 
            self.topic='All Books for Oracle Database Online Documentation Library'
            href='portal_booklist.htm'
            self.toc=self.full_dir..href
            self.title=href
            append(1,[[<LI><OBJECT type="text/sitemap">
            <param name="Name" value="Master Glossary">
            <param name="Local" value="nav\mgloss.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="Master Index">
            <param name="Local" value="nav\mindx.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="All SQL Keywords">
            <param name="Local" value="nav\sql_keywords.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="All Data Dictionary Views">
            <param name="Local" value="nav\catalog_views.htm">
          </OBJECT>]])
        else
            local _,title=self:getContent(self.toc)
            href='toc.htm'
            self.topic=title
            if self.toc:find('e13993') or self.toc:find('JAFAN') then
                self.topic='Oracle Database RAC FAN Events Java API Reference'
            elseif self.toc:find('JAXML') then
                self.topic='Oracle Database XML Java API Reference'
            end
        end
        append(1,"<LI><OBJECT type=\"text/sitemap\">")
        append(2,([[<param name="Name"  value="%s">]]):format(self.topic))
        append(2,([[<param name="Local" value="%s">]]):format(self.dir..'\\'..href))
        append(1,"</OBJECT></LI>")
        append(0,"</UL></BODY></HTML>")
        self.save(self.root..self.hhc,table.concat(hhc))
        return 
    end
    local root=json.decode(txt)
    local last_node
    local plsql_api
    local function travel(node,level)
        if node.t then
            node.t=node.t:gsub("([\1-\127\194-\244][\128-\193])", ''):gsub('%s*|+%s*',''):gsub('&.-;',''):gsub('\153',"'")
            last_node=node.h
            append(level+1,"<LI><OBJECT type=\"text/sitemap\">")
            append(level+2,([[<param name="Name"  value="%s">]]):format(node.t))
            append(level+2,([[<param name="Local" value="%s">]]):format(self.dir..'\\'..node.h))
            if self.dir==plsql_package_ref then
                local first=node.t:match('^[^%s]+')
                if not plsql_api then
                    plsql_api={}
                    self.plsql_api=plsql_api
                end
                if first:upper()==first and (level==1 or level==3) then --index package name and method
                    plsql_api[node.t]={name=node.t,ref={node.h}}
                end
            end
            if node.c then
                append(level+1,"</OBJECT><UL>") 
                for index,child in ipairs(node.c) do
                    travel(child,level+1)
                end
                if level==0 and last_node and not last_node:lower():find('^index%.htm') then
                    if self.exists(self.idx,true) then
                        append(1,"<LI><OBJECT type=\"text/sitemap\">")
                        append(2,[[<param name="Name"  value="Index">]])
                        append(2,([[<param name="Local" value="%s">]]):format(self.dir..'\\index.htm'))
                        append(1,"</OBJECT></LI>") 
                    end
                end
                append(level+1,"</UL></LI>") 
            else
                append(level+1,"</OBJECT></LI>") 
            end
        elseif #node>0 then
            for index,child in ipairs(node) do
                travel(child,level+1)
            end
        end

    end
    travel(root.docs[1],0)
    append(0,"</UL></BODY></HTML>")
    self.save(self.root..self.hhc,table.concat(hhc))
    self.topic=root.docs[1].t
    return self.topic
end

function builder:processHTML(file,level)
    if not file:lower():find("%.html?$") then return end
    local prefix=string.rep("%.%./",level)
    local txt=self.read(file)
    if self.is_javadoc then
        txt=txt:gsub('(<script)(.-)(</script>)',function(a,b,c)
            return a..b:gsub('&lt;','>'):gsub('&amp;','&'):gsub('&gt;','<')..c
        end)
        self.save(file,txt)
        return
    end
    --deal with the error message book
    if self.dir==errmsg_book then
        if not self.errmsg then self.errmsg={} end
        local doc=html.parse(txt):select("dt")
        local name=file:match("[^\\/]+$")
        for idx,node in ipairs(doc) do
            local a=node.nodes[1]
            local ref=a.attributes.id or a.attributes.name
            if a.name~='a' and a.nodes[1] then node,a=a,a.nodes[1] end
            if a.name=='a' and ref and not a.attributes.href then
                local content=node:getcontent():gsub('.*</a>%s*',''):gsub('<.->',''):gsub('%s+$',''):gsub('%s+',' ')
                if content:find(':') then
                    self.errmsg[#self.errmsg+1]={name=content:match('[^%s:]+'),ref={name..'#'..ref}}
                end
            end
        end
    end

    local count=0
    self.topic=self.topic or ""
    local dcommon_path=string.rep('../',level)..'dcommon'
    local header=[[<table summary="" cellspacing="0" cellpadding="0">
        <tr>
        <td align="left" valign="top"><b style="color:#326598;font-size:12px">%s<br/><i style="color:black">%s  Release 2</i></b></td>
        <td width="60" align="center" valign="top"><a href="index.htm"><img width="24" height="24" src="%s/gifs/index.gif" alt="Go to Index" /><br />
        <span class="icon">Index</span></a></td>
        <td width="70" align="center" valign="top"><a href="toc.htm"><img width="24" height="24" src="%s/gifs/doclib.gif" alt="Go to Documentation Home" /><br />
        <span class="icon">Content</span></a></td>
        <td width="80" align="center" valign="top"><a href="MS-ITS:nav.chm::/nav/portal_booklist.htm"><img width="24" height="24" src="%s/gifs/booklist.gif" alt="Go to Book List" /><br />
        <span class="icon">Book List</span></a></td>
        <td width="80" align="center" valign="top"><a href="MS-ITS:nav.chm::/nav/mindx.htm"><img width="24" height="24" src="%s/gifs/masterix.gif" alt="Go to Master Index" /><br />
        <span class="icon">Master Index</span></a></td>
        </tr>
        </table>]]
    header=header:format(self.topic:gsub("Oracle","Oracle&reg;"),(self.ver=='12c' and '12c' or '11g'),dcommon_path,dcommon_path,dcommon_path,dcommon_path)
    txt,count=txt:gsub("\n(%s+parent%.document%.title)","\n//%1"):gsub("&amp;&amp;","&&")
    txt,count=txt:gsub('%s*<header>.-</header>%s*','')
    txt=txt:gsub('%s*<footer>.*</footer>%s*','')
    txt=txt:gsub([[(%s*<script.-<%/script>%s*)]],'')
    txt=txt:gsub('%s*<a href="#BEGIN".-</a>%s*','')
    txt=txt:gsub('(<[^>]*) onload=".-"','%1')
    txt=txt:gsub([[(<a [^>]*)onclick=(["'"]).-%2]],'%1')
    txt=txt:gsub([[(<a [^>]*)target=(["'"]).-%2]],'%1')
    if count>0 then
        txt=txt:gsub('(<div class="IND .->)','%1'..header,1)
    end
    txt=txt:gsub('href="'..prefix..'([^"]+)%.pdf"([^>]*)>PDF<',function(s,d)
        return [[href="javascript:location.href='file:///'+location.href.match(/\:((\w\:)?[^:]+[\\/])[^:\\/]+\:/)[1]+']]..s:gsub("/",".")..[[.chm'"]]..d..'>CHM<'
    end)

    if level>0 then
        txt=txt:gsub([[(["'])]]..prefix..'index%.html?%1','%1MS-ITS:index.chm::/index.htm%1')
    end

    txt=txt:gsub('"('..prefix..'[^%.][^"]-)([^"\\/]+.html?[^"\\/]*)"',function(s,e)
        if e:find('.css',1,true) or e:find('.js',1,true) or s:find('dcommon') then return '"'..s..e..'"' end
        local t=s:gsub('^'..prefix,'')
        if t=='' then return '"'..s..e..'"' end
        e=e:gsub('(html?)%?[^#]+','%1')
        return '"MS-ITS:'..t:gsub("/",".").."chm::/"..t..e..'"'
    end)

    if level==2 and self.parent then
        txt=txt:gsub([["%.%./([^%.][^"]-)([^"\/]+.html?[^"\/]*)"]],function(s,e)
            t=self.parent..'/'..s
            e=e:gsub('(html?)%?[^#]+','%1')
            return '"MS-ITS:'..t:gsub("[\\/]+",".").."chm::/"..t:gsub("[\\/]+","/")..e..'"'
        end)
    end
    if not txt then print("file",file,"miss matched!") end
    self.save(file,txt)
end

function builder:listdir(base,level,callback)
    local root=target_doc_root..base
    local f=io.popen(([[dir /b/s %s*.htm]]):format(root))
    for file in f:lines() do
        local _,depth=file:sub(#root+1):gsub('[\\/]','')
        self:processHTML(file,level+depth)
        if callback then callback(file:sub(#target_doc_root+1),root) end
    end
    f:close()
    --if self.errmsg then self:buildIdx() end
end

function builder:buildHhp()
    local title=self.topic
    local hhp={string.format([[
        [OPTIONS]
        Binary TOC=Yes
        Binary Index=Yes
        Compiled File=%s.chm
        Contents File=%s
        Index File=%s
        Default Window=main
        Default Topic=%s\%s
        Default Font=
        Full-text search=Yes
        Auto Index=Yes
        Language=
        Title=%s
        Create CHI file=No
        Compatibility=1.1 or later
        Error log file=%s_errorlog.txt
        Full text search stop list file=
        Display compile progress=Yes
        Display compile notes=Yes

        [WINDOWS]
        main="%s","%s","%s","%s\%s","%s\%s",,,,,0x33520,222,0x70384E,[10,10,800,600],0xB0000,,,,,,0
        [FILES]
    ]],
        self.name,self.hhc,self.hhk,self.dir,self.title,title,self.name,
        title,self.hhc,self.hhk,self.dir,self.title,self.dir,self.title,self.name)}
    hhp[1]=hhp[1]:gsub("\n\t\t\t","\n")
    local function append(txt) hhp[#hhp+1]='\n'..txt end
    local _,depth=self.dir:gsub('[\\/]','')
    self:listdir(self.dir..'\\',self.depth,append)
    self.save(self.root..self.name..".hhp",table.concat(hhp))
    if self.errmsg then self:buildIdx() end
end

function builder:startBuild()
    print(string.rep('=',100).."\nBuilding "..self.dir)
    if self.dir:find('dcommon') then
        self:listdir(self.dir..'\\',self.depth)
    else
        self.errmsg=nil
        self:buildJson()
        self:buildIdx()
        self:buildHhp()
    end
end

function builder.BuildAll(parallel)
    local tasks={}
    local fd=io.popen(([[dir /s/b "%stoc.htm"]]):format(source_doc_root))
    local book_list={"nav"}
    for dir in fd:lines() do
        local name=dir:sub(#source_doc_root+1):gsub('[\\/][^\\/]+$','')
        if name~="nav" then book_list[#book_list+1]=name end
    end
    fd:close()
    builder:new('dcommon',true,true)
    for i,book in ipairs(book_list) do
        local this=builder:new(book,true,true)
        local idx=math.fmod(i-1,parallel)+1
        if i==1 then idx=parallel+1 end -- for nav
        if not tasks[idx] then tasks[idx]={} end
        local obj='"'..chm_builder..'" "'..target_doc_root..this.name..'.hhp"'
        if book:find(errmsg_book,1,true) then
            tasks[idx][#tasks[idx]+1]=obj
        else
            table.insert(tasks[idx],1,obj)
        end
    end
    table.insert(tasks[#tasks],'"'..chm_builder..'" "'..target_doc_root..'index.hhp"')
    os.execute('copy /Y html5.css '..target_doc_root..'nav\\css')
    for i=1,#tasks do
        builder.save(i..".bat",table.concat(tasks[i],"\n")..'\nexit\n')
        if i<=parallel then
            os.execute('start "Compiling CHMS '..i..'" '..i..'.bat')
        end
    end
    print('Since compiling nav.chm takes longer time, please execute '..(parallel+1)..'.bat separately if necessary.')
    builder.BuildBatch()
end

function builder.BuildBatch()
    local dir=target_doc_root
    builder.topic='Oracle 12c Documents(E66230_01)'
    if errmsg_book~='ERRMG' then
        builder.topic='Oracle 11g Documents(E11882_01)'
    end
    builder.save(dir..'index.htm',builder.read(source_doc_root..'index.htm'))
    builder.processHTML(builder,dir..'index.htm',0)
    local hhc=[[<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
<meta name="generator" content="Microsoft&reg; HTML Help Workshop 4.1">
<!-- Sitemap 1.0 -->
</head>
<body>
   <OBJECT type="text/site properties">
     <param name="Window Styles" value="0x800225">
     <param name="comment" value="title:Online Help">
     <param name="comment" value="base:index.htm">
   </OBJECT>
   <UL>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="Portal">
            <param name="Local" value="index.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="CHM File Overview">
            <param name="Local" value="chm.htm">
          </OBJECT>
   </UL>
]]
    local hhk=[[
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
<meta name="generator" content="Microsoft&reg; HTML Help Workshop 4.1">
<!-- Sitemap 1.0 -->
<BODY>
   <OBJECT type="text/site properties">
     <param name="Window Styles" value="0x800025">
     <param name="comment" value="title:Online Help">
     <param name="comment" value="base:index.htm">
   </OBJECT>
<OBJECT type="text/site properties">
    <param name="FrameName" value="right">
</OBJECT>
<UL>
    <LI> <OBJECT type="text/sitemap">
        <param name="Name" value="copyright">
        <param name="Local" value="dcommon\html\cpyr.htm">
        </OBJECT>
</UL>
</BODY>
</HTML>
    ]]
    local hhp=[[
[OPTIONS]
Binary TOC=No
Binary Index=Yes
Compiled File=index.chm
Contents File=index.hhc
Index File=index.hhk
Default Window=main
Default Topic=index.htm
Default Font=
Full-text search=Yes
Auto Index=Yes
Language=
Title=]]..builder.topic..[[
Create CHI file=No
Compatibility=1.1 or later
Error log file=..\_errorlog.txt
Full text search stop list file=
Display compile progress=Yes
Display compile notes=Yes

[WINDOWS]
main="]]..builder.topic..[[","index.hhc","index.hhk","index.htm","index.htm",,,,,0x33520,222,0x101846,[10,10,800,600],0xB0000,,,,,,0

[FILES]
index.htm
chm.htm
[MERGE FILES]
]]
    local hhclist={}
    local f=io.popen(([[dir /b "%s*.hhc"]]):format(dir))
    for name in f:lines() do
        local n=name:sub(-4)
        local c=name:sub(1,-5)
        if n==".hhc" and name~="index.hhc" then
            local txt=builder.read(dir..c..".hhp","r")
            local title=txt:match("Title=([^\n]+)")
            hhclist[#hhclist+1]={file=c,title=title,chm=c..".chm"}
        end
    end
    f:close()

    table.sort(hhclist,function(a,b) return a.title<b.title end)
    local html={'<table border><tr><th align="left" style="font-size:20px">CHM File Name</th><th align="left" style="font-size:20px">Book Name</th></tr>'}
    local item='   <OBJECT type="text/sitemap">\n     <param name="Merge" value="%s.chm::/%s.hhc">\n   </OBJECT>\n'
    for i,book in ipairs(hhclist) do
        html[#html+1]=[[<tr><td><a href="javascript:location.href='file:///'+location.href.match(/\:((\w\:)?[^:]+[\\/])[^:\\/]+\:/)[1]+']]..book.chm..[['">]]..book.chm..[[</a></td><td>]]..book.title..[[</td></tr>]]
        hhc=hhc..(item):format(book.file,book.file)
        hhp=hhp..book.chm.."\n"
    end
    html=table.concat(html,'\n')..'</table><br/><p style="font-size:12px">@2016 by hyee https://github.com/hyee/Oracle-DB-Document-CHM-builder</p>'
    
    hhc=hhc..'</BODY></HTML>'
    builder.save(dir.."chm.htm",html)
    builder.save(dir.."index.hhp",hhp)
    builder.save(dir.."index.hhc",hhc)
    builder.save(dir.."index.hhk",hhk)
end

--builder:new('ARPLS',1,1)
builder.BuildAll(6)
--builder.BuildBatch()