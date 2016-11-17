
require "math"
local html=require("htmlparser")
local json=require("json")
local io,pairs,ipairs=io,pairs,ipairs
local chm_builder=[[C:\Program Files (x86)\HTML Help Workshop\hhc.exe]]
local source_doc_root=[[f:\BM\E66230_01\]]
local target_doc_root=[[f:\BM\newdoc12\]]


--local function print(txt)

local reps={
	["\""]="&quot;",
	["<"]="&lt;",
	[">"]="&gt;"
}
function rp(s) return reps[s] end
function strip(str)
	return str:gsub("[\n\r\b]",""):gsub("^[ ,]*(.-)[ ,]*$", "%1"):gsub("  +"," "):gsub("[\"<>]",rp):gsub("%s*&reg;?%s*"," ")
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
	setmetatable(o,self)
	self.__index=self
	if build then 
		o:startBuild()
	end
	return o
end

function builder.exists(file,silent)
	local f,err=io.open(file,'r')
	if not f then
		if not silent then print(err) end
		return false
	else
		f:close()
		return true 
	end
end

function builder.save(path,text)
	if type(path)=="table" then
		print(debug.traceback())
	end
	local f=io.open(path,"w")
	f:write(text)
	f:close()
end

function builder.getContent(self,file)
	--print(file)
	local f=io.open(file,"r")
	if not f then return print('Unable to open file '..file) end
	local txt=f:read("*a")
	f:close() 
	--print(1)
	local title=txt:match([[<meta name="doctitle" content="([^"]+)"]])
	if not title then title=txt:match("<title>(.-)</title>") end
	title=title:gsub("%s*&reg;?%s*"," "):gsub("([\1-\127\194-\244][\128-\193])", ''):gsub('%s*|+%s*',''):gsub('&.-;','')
	local root=html.parse(txt):select("div[class^='IND']")
	return root and root[1] or {} ,title
end

function builder.buildIdx(self)
	local c=self:getContent(self.idx)
	if not c then return end
	local hhk=
	{[[<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><HEAD>
		<meta content="Microsoft HTML Help Workshop 4.1" name="GENERATOR">
		<!-- Sitemap 1.0 -->
	  </HEAD>
	  <BODY><UL>]]}
	local function append(level,txt)
		hhk[#hhk+1]='\n    '..string.rep("  ",level).. txt
	end

	local nodes=c:select("dd[class*='ix']")
	local tree={}
	local treenode={}
	for _,node in ipairs(nodes) do
		local level=tonumber(node.attributes.class:match('l(%d+)ix'))
		if level then
			local n={name=node:getcontent(),ref={}}
			local found=false
			for _,a in ipairs(node.nodes) do
				if a.name=='a' then
					if not found then found,n.name=true,n.name:gsub(',?%s<a.*','') end
					n.ref[#n.ref+1]=self.dir..'\\'..a.attributes.href
				end
			end
 			treenode[level]=n
			if level>1 then
				table.insert(treenode[level-1],n)
				if #treenode[level-1].ref==0 then treenode[level-1].ref=n.ref end
			else
				tree[#tree+1]=n
			end
		end
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
					append(level+2,([[<param name="Local" value="%s">]]):format(node.ref[i]))
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

function builder.buildJson(self)
	self.hhc=self.name..".hhc"
	local hhc={
    [[<HTML><HEAD>
		<meta content="Microsoft HTML Help Workshop 4.1" name="GENERATOR">
		<!-- Sitemap 1.0 -->
	  </HEAD>
	  <BODY>
		<OBJECT type="text/site properties">
		  <param name="Window Styles" value="0x800025">
		  <param name="comment" value="title:Online Help">
     	  <param name="comment" value="base:toc.htm">
		</OBJECT><UL>]]}
	local function append(level,txt)
		hhc[#hhc+1]='\n    '..string.rep("  ",level*2).. txt
	end

	local f=io.open(self.json)
	if not f then
		local title,href
		if self.toc:lower():find('\\nav\\') then 
			self.topic='All Books for Oracle Database Online Documentation Library'
			href='portal_booklist.htm'
			self.toc=self.full_dir..href
			self.title=href
			append(1,[[<LI><OBJECT type="text/sitemap">
            <param name="Name" value="Portal">
            <param name="Local" value="nav\portal_1.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="Master Glossary">
            <param name="Local" value="nav\mgloss.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="Master Index">
            <param name="Local" value="nav\mindx.htm">
          </OBJECT>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="SQL Keywords">
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
			if self.toc:find('e13993') then
				self.topic='Oracle Database RAC FAN Events Java API Reference'
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
	local txt=f:read("*a")
	f:close() 
	local root=json.decode(txt)
	local last_node
	local function travel(node,level)
		if node.t then
			node.t=node.t:gsub("([\1-\127\194-\244][\128-\193])", ''):gsub('%s*|+%s*',''):gsub('&.-;','')
			last_node=node.h
			append(level+1,"<LI><OBJECT type=\"text/sitemap\">")
			append(level+2,([[<param name="Name"  value="%s">]]):format(node.t))
			append(level+2,([[<param name="Local" value="%s">]]):format(self.dir..'\\'..node.h))
			if node.c then
				append(level+1,"</OBJECT><UL>") 
				for index,child in ipairs(node.c) do
					travel(child,level+1)
				end
				if level==0 and last_node and not last_node:lower():find('^index%.htm') then
					local f=io.open(self.idx,'r')
					if f then
						f:close()
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

function builder:listdir(base,level,callback)
	local root=target_doc_root..base
	local function parseHtm(file,level)
		if not file:lower():find("%.html?$") then return end
		local prefix=string.rep("%.%./",level)
		local f=io.open(file,'r')
		local txt=f:read("*a")
		local count=0
		f:close()
		self.topic=self.topic or ""
		local header=[[<table summary="" cellspacing="0" cellpadding="0">
			<tr>
			<td align="left" valign="top"><b style="color:#326598;font-size:24px">]]..self.topic:gsub("Oracle","Oracle&reg;")..[[</b></td>
			<td width="70" align="center" valign="top"><a href="toc.htm"><img width="24" height="24" src="../../dcommon/gifs/doclib.gif" alt="Go to Documentation Home" /><br />
			<span class="icon">Content</span></a></td>
			<td width="60" align="center" valign="top"><a href="index.htm"><img width="24" height="24" src="../../dcommon/gifs/index.gif" alt="Go to Index" /><br />
			<span class="icon">Index</span></a></td>
			<td width="80" align="center" valign="top"><a href="MS-ITS:nav.chm::/nav/portal_booklist.htm"><img width="24" height="24" src="../../dcommon/gifs/booklist.gif" alt="Go to Book List" /><br />
			<span class="icon">Book List</span></a></td>
			<td width="80" align="center" valign="top"><a href="MS-ITS:nav.chm::/nav/mindx.htm"><img width="24" height="24" src="../../dcommon/gifs/masterix.gif" alt="Go to Master Index" /><br />
			<span class="icon">Master Index</span></a></td>
			</tr>
			</table>]]
		txt,count=txt:gsub("\n(%s+parent%.document%.title)","\n//%1"):gsub("&amp;&amp;","&&")
		txt,count=txt:gsub('%s*<header>.-</header>%s*','')
		txt=txt:gsub('%s*<footer>.*</footer>%s*','')
		txt=txt:gsub([[%s*<script type[^>]*javascript[^>]*src.-</script>%s*]],'')
		txt=txt:gsub([[(<script [^>]*javascript.->)(.-)(</script>)]],function(head,content,foot)
				return head..content:gsub('&lt;','>')..foot
			end)
		txt=txt:gsub('%s*<a href="#BEGIN".-</a>%s*','')
		txt=txt:gsub([[(<a [^>]*)onclick=(["'"]).-%2]],'%1')
		txt=txt:gsub([[(<a [^>]*)target=(["'"]).-%2]],'%1')
		if count>0 then
			txt=txt:gsub('(<div class="IND .->)','%1'..header,1)
		end
		txt=txt:gsub('href="'..prefix..'([^"]+)%.pdf"([^>]*)>PDF<',function(s,d)
			return [[href="javascript:location.href='file:///'+location.href.match(/\:((\w\:)?[^:]+[\\/])[^:\\/]+\:/)[1]+']]..s:gsub("/",".")..[[.chm'"]]..d..'>CHM<'
		end)

		txt=txt:gsub('"('..prefix..'[^"]-)([^"\\/]+.html?[^"\\/]*)"',function(s,e)
			if e:find('.css',1,true) or e:find('.js',1,true) or s:find('dcommon') then return '"'..s..e..'"' end
			local t=s:gsub('^'..prefix,'')
			if t=='' then return '"'..s..e..'"' end
			return '"MS-ITS:'..t:gsub("/",".").."chm::/"..t..e..'"'
		end)

		if level==2 then
			txt=txt:gsub([["%.%./([^%.][^"]-)([^"\/]+.html?[^"\/]*)"]],function(s,e)
				t=self.parent..'/'..s
				return '"MS-ITS:'..t:gsub("[\\/]+",".").."chm::/"..t:gsub("[\\/]+","/")..e..'"'
			end)
		end
		if not txt then print("file",file,"miss matched!") end
		self.save(file,txt)
	end

	local f=io.popen(([[dir /b/s %s*.htm]]):format(root))
	for file in f:lines() do
		parseHtm(file,level)
		if callback then callback(file:sub(#target_doc_root+1),root) end
	end
	f:close()
end

function builder.buildHhp(self)
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
end

function builder:startBuild()
	print(string.rep('=',100).."\nBuilding "..self.dir)
	if self.dir:find('dcommon') then
		self:listdir(self.dir..'\\',self.depth)
	else
		self:buildIdx()
		self:buildJson()
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
		tasks[idx][#tasks[idx]+1]='"'..chm_builder..'" "'..target_doc_root..this.name..'.hhp"'
	end

	os.execute('copy /Y html5.css '..target_doc_root..'nav\\css')
	for i=1,#tasks do
		builder.save(i..".bat",table.concat(tasks[i],"\n"))
		if i<=parallel then
			os.execute('start "Compiling CHMS '..i..'" '..i..'.bat')
		end
	end
	print('Since compiling nav.chm takes longer time, please execute '..(parallel+1)..'.bat separately if necessary.')
	--builder.BuildBatch()
end

function builder.BuildBatch()
	local dir=target_doc_root
	local hhc=[[	
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
<meta name="GENERATOR" content="Microsoft&reg; HTML Help Workshop 4.1">
<!-- Sitemap 1.0 -->
</HEAD>
<BODY>
   <OBJECT type="text/site properties">
     <param name="Window Styles" value="0x800025">
     <param name="comment" value="title:Online Help">
     <param name="comment" value="base:index.htm">
   </OBJECT>
   <UL>
      <LI><OBJECT type="text/sitemap">
            <param name="Name" value="CHM File List">
            <param name="Local" value="index.htm">
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
Default Topic=ms-its:nav.chm::/nav/portal_booklist.htm
Default Font=
Full-text search=Yes
Auto Index=Yes
Language=
Title=Oracle 12G Documents(E66230_01)
Create CHI file=No
Compatibility=1.1 or later
Error log file=..\_errorlog.txt
Full text search stop list file=
Display compile progress=Yes
Display compile notes=Yes

[WINDOWS]
main="Oracle 12G Documents(E66230_01)","index.hhc","index.hhk","ms-its:nav.chm::/nav/portal_booklist.htm","ms-its:nav.chm::/nav/portal_booklist.htm",,,,,0x33520,222,0x101846,[10,10,800,600],0xB0000,,,,,,0

[FILES]
index.htm

[MERGE FILES]
]]
	local hhclist={}
	local f=io.popen(([[dir /b "%s*.hhc"]]):format(dir))
	for name in f:lines() do
		local n=name:sub(-4)
		local c=name:sub(1,-5)
		if n==".hhc" and name~="index.hhc" then
			local f1=io.open(dir..c..".hhp","r")
			local title=f1:read("*a"):match("Title=([^\n]+)")
			f1:close()
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
	builder.save(dir.."index.htm",html)
	builder.save(dir.."index.hhp",hhp)
	builder.save(dir.."index.hhc",hhc)
	builder.save(dir.."index.hhk",hhk)
end

builder:new([[dcommon]],1,1)
--builder.BuildAll(6)
--builder.BuildBatch()