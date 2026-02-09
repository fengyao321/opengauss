-- gms_xmlparser
CREATE SCHEMA gms_xmlparser;
CREATE SCHEMA gms_xmldom;

CREATE TYPE gms_xmlparser.parser;

CREATE FUNCTION gms_xmlparser.parser_in(cstring)
RETURNS gms_xmlparser.parser
AS 'MODULE_PATHNAME','gms_xmlparser_parser_in'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;

CREATE FUNCTION gms_xmlparser.parser_out(gms_xmlparser.parser)
RETURNS cstring
AS 'MODULE_PATHNAME','gms_xmlparser_parser_out'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;

CREATE TYPE gms_xmlparser.parser(
  internallength = 8,
  input = gms_xmlparser.parser_in,
  output = gms_xmlparser.parser_out
);

CREATE TYPE gms_xmldom.domdocument;

CREATE FUNCTION gms_xmldom.document_in(cstring)
RETURNS gms_xmldom.domdocument
AS 'MODULE_PATHNAME','document_in'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;

CREATE FUNCTION gms_xmldom.document_out(gms_xmldom.domdocument)
RETURNS cstring
AS 'MODULE_PATHNAME','document_out'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;

CREATE TYPE gms_xmldom.domdocument(
  internallength = 16,
  input = gms_xmldom.document_in,
  output = gms_xmldom.document_out
);


CREATE FUNCTION gms_xmlparser.parse(varchar2)
RETURNS gms_xmldom.domdocument
AS 'MODULE_PATHNAME','gms_xmlparser_parse4func'
LANGUAGE C STABLE SHIPPABLE NOT FENCED PACKAGE;

CREATE FUNCTION gms_xmlparser.parse4proc(gms_xmlparser.parser,varchar2)
RETURNS void
AS 'MODULE_PATHNAME','gms_xmlparser_parse4proc'
LANGUAGE C STABLE SHIPPABLE NOT FENCED;

CREATE OR REPLACE PROCEDURE gms_xmlparser.parse(parser gms_xmlparser.parser, str varchar2) PACKAGE
AS
DECLARE
  error_message TEXT;
BEGIN
  PERFORM gms_xmlparser.parse4proc(parser,str);
  EXCEPTION
    WHEN OTHERS THEN
      error_message := SQLERRM;
            RAISE EXCEPTION '%', error_message;
END;

CREATE FUNCTION gms_xmlparser.newparser()
RETURNS gms_xmlparser.parser
AS 'MODULE_PATHNAME','gms_xmlparser_newparser'
LANGUAGE C STABLE SHIPPABLE NOT FENCED;

CREATE FUNCTION gms_xmlparser.freeparser4func(gms_xmlparser.parser)
RETURNS void
AS 'MODULE_PATHNAME','gms_xmlparser_freeparser'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;

CREATE OR REPLACE PROCEDURE gms_xmlparser.freeparser(parser gms_xmlparser.parser)
AS
DECLARE
    error_message TEXT;
BEGIN
  PERFORM gms_xmlparser.freeparser4func(parser);
  EXCEPTION
    WHEN OTHERS THEN
      error_message := SQLERRM;
            RAISE EXCEPTION '%', error_message;
END;

CREATE FUNCTION gms_xmlparser.parsebuffer4func(parser gms_xmlparser.parser, str varchar2)
RETURNS void
AS 'MODULE_PATHNAME','gms_xmlparser_parsebuffer'
LANGUAGE C STABLE SHIPPABLE NOT FENCED;

CREATE OR REPLACE PROCEDURE gms_xmlparser.parsebuffer(parser gms_xmlparser.parser, str varchar2)
AS
DECLARE
  error_message TEXT;
BEGIN
  PERFORM gms_xmlparser.parsebuffer4func(parser,str);
  EXCEPTION
    WHEN OTHERS THEN
      error_message := SQLERRM;
            RAISE EXCEPTION '%', error_message;
END;

CREATE FUNCTION gms_xmlparser.parseclob4func(gms_xmlparser.parser, varchar2)
RETURNS void
AS 'MODULE_PATHNAME','gms_xmlparser_parseclob'
LANGUAGE C STABLE SHIPPABLE NOT FENCED;

CREATE OR REPLACE PROCEDURE gms_xmlparser.parseclob(parser gms_xmlparser.parser, str varchar2)
AS
DECLARE
  error_message TEXT;
BEGIN
  PERFORM gms_xmlparser.parseclob4func(parser,str);
  EXCEPTION
    WHEN OTHERS THEN
      error_message := SQLERRM;
            RAISE EXCEPTION '%', error_message;
END;

CREATE FUNCTION gms_xmlparser.getdocument(gms_xmlparser.Parser)
RETURNS gms_xmldom.domdocument
AS 'MODULE_PATHNAME','gms_xmlparser_getdocument'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;

CREATE FUNCTION gms_xmldom.freedocument(gms_xmldom.domdocument)
RETURNS void
AS 'MODULE_PATHNAME','freedocument'
LANGUAGE C STRICT STABLE SHIPPABLE NOT FENCED;