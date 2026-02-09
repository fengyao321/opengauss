create extension gms_xmlparser;
--error case test
declare
parser gms_xmlparser.parser;
xml_data clob;
begin
xml_data := '';
parser := gms_xmlparser.newparser();
gms_xmlparser.parseclob(parser, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data clob;
begin
parser := gms_xmlparser.newparser();
gms_xmlparser.parseclob(parser, NULL);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
begin
xml_data := '';
parser := gms_xmlparser.newparser();
gms_xmlparser.parsebuffer(parser, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
begin
parser := gms_xmlparser.newparser();
gms_xmlparser.parsebuffer(parser, NULL);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parsebuffer(NULL, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data CLOB;
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parseclob(NULL, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
begin
parser := gms_xmlparser.newparser();
gms_xmlparser.freeparser(NULL);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parse(NULL, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parse(parser, NULL);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
begin
xml_data := '';
parser := gms_xmlparser.newparser();
gms_xmlparser.parse(parser, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
xml_dom gms_xmldom.domdocument;
begin
xml_data := '';
parser := gms_xmlparser.newparser();
xml_dom := gms_xmlparser.parse(xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
xml_dom gms_xmldom.domdocument;
begin
xml_data := '';
parser := gms_xmlparser.newparser();
xml_dom := gms_xmlparser.parse(NULL);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
xml_dom gms_xmldom.domdocument;
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parsebuffer(parser, xml_data);
xml_dom := gms_xmlparser.getdocument(NULL);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_dom gms_xmldom.domdocument;
begin
parser := gms_xmlparser.newparser();
xml_dom := gms_xmlparser.getdocument(parser);
gms_xmlparser.freeparser(parser);
end;
/

declare
xml_dom gms_xmldom.domdocument;
begin
gms_xmldom.freedocument(xml_dom);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(20);
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parsebuffer(parser, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(20);
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parse(parser, xml_data);
gms_xmlparser.freeparser(parser);
end;
/

declare
parser gms_xmlparser.parser;
xml_data varchar2(20);
xml_dom gms_xmldom.domdocument;
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
xml_dom := gms_xmlparser.parse(xml_data);
gms_xmldom.freedocument(xml_dom);
end;
/

--normal case test
declare
parser gms_xmlparser.parser;
xml_data varchar2(2000);
lob_data CLOB;
dom_doc gms_xmldom.domdocument;
begin
xml_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
lob_data := '<?xml version="1.0" encoding="UTF-8"?>
<messege>
	<warning>
		Hello World!
	</warning>
</messege>';
parser := gms_xmlparser.newparser();
gms_xmlparser.parsebuffer(parser, xml_data);
dom_doc := gms_xmlparser.getdocument(parser);
gms_xmldom.freedocument(dom_doc);

gms_xmlparser.parseclob(parser, lob_data);
dom_doc := gms_xmlparser.getdocument(parser);
gms_xmldom.freedocument(dom_doc);

gms_xmlparser.parse(parser, xml_data);
dom_doc := gms_xmlparser.getdocument(parser);
gms_xmldom.freedocument(dom_doc);

dom_doc := gms_xmlparser.parse(xml_data);
gms_xmldom.freedocument(dom_doc);
gms_xmlparser.freeparser(parser);
end;
/
