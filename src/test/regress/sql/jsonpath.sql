DROP DATABASE IF EXISTS test_jsonpath_a;
CREATE DATABASE test_jsonpath_a;
\c test_jsonpath_a;

CREATE TABLE t (name VARCHAR2(100));
INSERT INTO t VALUES ('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}, 1]');
INSERT INTO t VALUES ('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}, [1, 2, 3]]');
INSERT INTO t VALUES ('[{"first":"Mary"}, {"last":"Jones"}]');
INSERT INTO t VALUES ('[{"first":"Jeff"}, {"last":"Williams"}]');
INSERT INTO t VALUES ('[{"first":"Jean"}, {"middle":"Anne"}, {"last":"Brown"}]');
INSERT INTO t VALUES ('[{"first":"Jean"}, {"middle":"Anne"}, {"middle":"Alice"}, {"last":"Brown"}]');
INSERT INTO t VALUES ('[{"first":1}, {"middle":2}, {"last":3}]');
INSERT INTO t VALUES (NULL);
INSERT INTO t VALUES ('This is not well-formed JSON data');


CREATE TABLE families (family_doc CLOB);
INSERT INTO families
VALUES ('{"family" : {"id":10, "ages":[40,38,12], "address" : {"street" : "10 Main Street"}}}');
INSERT INTO families
VALUES ('{"family" : {"id":11, "ages":[42,40,10,5], "address" : {"street" : "200 East Street", "apt" : 20}}}');
INSERT INTO families
VALUES ('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}');

INSERT INTO families VALUES ('This is not well-formed JSON data');

-- JsonPath grammar
SELECT '$[$index]'::jsonpath;
SELECT name FROM t WHERE JSON_EXISTS(name, '$');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[0]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[*]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[$index]');
SELECT name FROM t WHERE JSON_EXISTS(name, 'strict $[*]');
SELECT name FROM t WHERE JSON_EXISTS(name, 'lax $[*]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[99]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[last]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[last] + 1');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[last - 2]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[last * 2]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[2 - last]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[0,2]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[2,0,1]'); 
SELECT name FROM t WHERE JSON_EXISTS(name, '$[0 to 2]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[3 to 3]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[2 to 0]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[false to true]');
SELECT name FROM t WHERE JSON_EXISTS(name, '2');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[2].*.*');
SELECT family_doc FROM families WHERE JSON_EXISTS(family_doc, '$.family');
SELECT family_doc FROM families WHERE JSON_EXISTS(family_doc, '$.*');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[3][1]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[1].last');
SELECT family_doc FROM families WHERE JSON_EXISTS(family_doc, '$.family.address.apt');
SELECT family_doc FROM families WHERE JSON_EXISTS(family_doc, '$.family.ages[2]');

-- syntax error in jsonpath
SELECT name FROM t WHERE JSON_EXISTS(name, '$[-1]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[0b10]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[1');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[1+2]');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[1.1]');
SELECT name FROM t WHERE JSON_EXISTS(name, 'NULL');
SELECT name FROM t WHERE JSON_EXISTS(name, NULL);

drop table if exists t_JsonExists_Case0009;
CREATE TABLE t_JsonExists_Case0009( col1 VARCHAR2 (2000));

INSERT INTO t_JsonExists_Case0009 VALUES (null);

select col1 from t_JsonExists_Case0009 where json_exists(col1,' ');

select col1 from t_JsonExists_Case0009 where json_exists(col1,' ' FALSE on ERROR);
select col1 from t_JsonExists_Case0009 where json_exists(col1,' ' TRUE on ERROR);
select col1 from t_JsonExists_Case0009 where json_exists(col1,' ' ERROR on ERROR);
drop table t_JsonExists_Case0009;

-- json_exists
SELECT name FROM t WHERE JSON_EXISTS(name, '$[0].first');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[1,2].last');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[1 to 2].last');

SELECT name FROM t WHERE JSON_EXISTS(name, '$[1].first');
SELECT name FROM t WHERE JSON_EXISTS(name, '$[0].first[1]');

SELECT name FROM t WHERE JSON_EXISTS(NULL, '$');
SELECT JSON_EXISTS('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]', '$[0].first');
SELECT JSON_EXISTS('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]', '$[2 to 1].*');
SELECT JSON_EXISTS('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]', '$[*].last');
SELECT JSON_EXISTS('This is not well-formed JSON data', '$[0].first');

-- json_exists with on error
SELECT name FROM t WHERE JSON_EXISTS(name, '$' FALSE ON ERROR);
SELECT name FROM t WHERE JSON_EXISTS(name, '$' TRUE ON ERROR);
SELECT name FROM t WHERE JSON_EXISTS(name, '$' ERROR ON ERROR);

SELECT JSON_EXISTS('This is not well-formed JSON data', '$[0].first' FALSE ON ERROR);
SELECT JSON_EXISTS('This is not well-formed JSON data', '$[0].first' TRUE ON ERROR);
SELECT JSON_EXISTS('This is not well-formed JSON data', '$[0].first' ERROR ON ERROR);

select json_exists('{"name":"胡小威" , "age":20 , "male":true}','$[0].name'); -- t
select json_exists('{"name":"胡小威" , "age":20 , "male":true}','$[1].name'); -- f
select json_exists('{"name":"胡小威" , "age":20 , "male":true}','$.name[0]'); -- t
select json_exists('{"name":"胡小威" , "age":20 , "male":true}','$.name[0][0,1][0 to 3][0]'); -- t
select json_exists('{"name":"胡小威" , "age":20 , "male":true}','$.name[0][0,1][1 to 3][0]'); -- f
SELECT JSON_EXISTS('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]', '$.first'); -- t
SELECT JSON_EXISTS('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]', '$.first[0][0][0][0]'); -- t
SELECT JSON_EXISTS('[1, "aBdC", "ab\nadc", "111\nabc", "^ab.*c$"]', '$[*] ? (@ like_regex "^ab.*c")');
SELECT JSON_EXISTS('[1, "aBdC", "ab\nadc", "111\nabc", "^ab.*c$"]', '$[*] ? (@ like_regex "^ab.*c" flag "i")');

PREPARE stmt1 AS SELECT JSON_EXISTS($1,$2);
EXECUTE stmt1('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]','$[0].first');
EXECUTE stmt1('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]','$[0].last');
EXECUTE stmt1('This is not well-formed JSON data','$[0].last');
DEALLOCATE PREPARE stmt1;
PREPARE stmt1 AS SELECT JSON_EXISTS($1,$2 TRUE ON ERROR);
EXECUTE stmt1('This is not well-formed JSON data','$[0].last');
DEALLOCATE PREPARE stmt1;
PREPARE stmt1 AS SELECT JSON_EXISTS($1,$2 FALSE ON ERROR);
EXECUTE stmt1('This is not well-formed JSON data','$[0].last');
DEALLOCATE PREPARE stmt1;
PREPARE stmt1 AS SELECT JSON_EXISTS($1,$2 ERROR ON ERROR);
EXECUTE stmt1('This is not well-formed JSON data','$[0].last');
DEALLOCATE PREPARE stmt1;

-- json_textcontains
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', '10');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', '25, 5');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', 'West');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', 'Oak Street');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', 'Oak Street'::cstring);
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', 'oak street');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', '25 23, Oak Street');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', 'Oak Street 10');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', '12 25 23 300 Oak Street 10');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family.id', 'Oak Street');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.family', 'ak street');

drop table if exists json_data1;
CREATE TABLE json_data1(json_col CLOB);  
INSERT INTO json_data1 VALUES ('{"name":"web"}');
select * from json_data1 where json_textcontains(json_col,'$.site','nothing');
drop table json_data1;

PREPARE stmt2 AS SELECT JSON_TEXTCONTAINS($1, $2, $3);
EXECUTE stmt2(NULL, '$.family', 'data');
EXECUTE stmt2('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
             , '$.family', '12');
EXECUTE stmt2('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
             , '$.family', 'K STREET');
EXECUTE stmt2('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
            , NULL, 'data');

drop table families;
CREATE TABLE families (family_doc CLOB);
INSERT INTO families VALUES ('{"ages":[11,40,10]}');
INSERT INTO families VALUES ('{"ages":[12,38,10]}');
INSERT INTO families VALUES ('{"ages":[40,38,10]}');
INSERT INTO families VALUES ('{"ages":[40,48,10]}');

SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.ages', '12,40');
SELECT family_doc FROM families WHERE JSON_TEXTCONTAINS(family_doc, '$.ages', '0');

SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}', '$.family', 'Oak Street## 10');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "!@$%300 Oak Street", "apt" : 10}}}', '$.family', '300%@ Oak Street## 10');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "!@$%300 Oak Street", "apt" : 10}}}', '$.family', '300%@00 Oak Street## 10');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "!@$%300 Oak Street", "apt" : 10}}}', '$.family', '     Oak    ');
SELECT JSON_TEXTCONTAINS('This is not well-formed JSON data', '$.family', 'data');
SELECT JSON_TEXTCONTAINS(NULL, '$.family', 'data');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
                        , '$.family', '12');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
                        , '$.family', '12, OAK STREET');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
                        , '$.family', 'K STREET');
SELECT JSON_TEXTCONTAINS('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}'
                        , NULL, 'data');

select json_textcontains('{ "zebra" : { "name" : "Marty",   
                       "stripes" : ["Black","White"],  
                       "handler" : "Bob" }}','$','Marty');
select json_textcontains('{ "zebra" : { "name" : "Marty",   
                       "stripes" : ["Black","White"],  
                       "handler" : "Bob" }}','$.zebra.name','Marty');
select json_textcontains('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}',
                         '$.family.address.street','300');
select json_textcontains('{
    "name":"web",
    "num":3,
    "sites": [
        { "name":"Google", "info":[ "Android", "Google Search", "Googlee" ] },
        { "name":"Runoob", "info":[ "book", "tool", "wechat" ] },
        { "name":"Taobao", "info":[ "taobao", "shop" ] }
    ]
}', '$.sites.info.name','shop');
select json_textcontains('{
    "name":"web",
    "num":3,
    "sites": [
        { "name":"Google", "info":[[ {"name":"Android"}, {"name":"Google Search"}, {"name":"Googlee"} ]] },
        { "name":"Runoob", "info":[[ {"name":"book"}, {"name":"tool"}, "wechat" ]] },
        { "name":"Taobao", "info":[[ {"name":"taobao"}, "shop" ]] },
        { "name":null, "info":[[ {"name":true}, {"name":false} ]] }
    ]
}', '$.sites.info.name','Androidd,Search,Googlee');
select json_textcontains('{
    "name":"web",
    "num":3,
    "sites": [
        { "name":"Google", "info":[[ {"name":"Android"}, {"name":"Google Search"}, {"name":"Googlee"} ]] },
        { "name":"Runoob", "info":[[ {"name":"book"}, {"name":"tool"}, "wechat" ]] },
        { "name":"Taobao", "info":[[ {"name":"taobao"}, "shop" ]] }
    ]
}', '$.*.*.*[*][*][*]','Androidd,Search,Googlee');
select json_textcontains('{
    "name":"web",
    "num":3,
    "sites": [
        { "name":"Google", "info":[[ {"name":"Android"}, {"name":"Google Search"}, {"name":"Googlee"} ]] },
        { "name":"Runoob", "info":[[ {"name":"book"}, {"name":"tool"}, "wechat" ]] },
        { "name":"Taobao", "info":[[ {"name":"taobao"}, "shop" ]] }
    ]
}', '$.**.name','Androidd,Search,Googlee');
SELECT json_textcontains('[-0.2, 1.1, 2.7]', '$[*].abs().floor().ceiling()', '0 1 2');
SELECT json_textcontains('[-0.2, 1.1, 2.7]', '$[*].size().type()', 'number');
SELECT json_textcontains('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}', '$.family.keyvalue()', 'address');

create or replace procedure p_JsonTextcontains_Case0011(col1 text,col2 text,col3 text)
as
val1 bool;
begin
val1=json_textcontains(col1,col2,col3);--强转成cstring
raise notice 'result=%',val1;
end;
/

call p_JsonTextcontains_Case0011('{"family" : {"id":12, "ages":[25,23], "address" : {"street" : "300 Oak Street", "apt" : 10}}}',
                                 '$.family','25,38');

drop table if exists t_JsonExists_Case0006;
CREATE TABLE t_JsonExists_Case0006(po_document VARCHAR2 (2000));
INSERT INTO t_JsonExists_Case0006
  VALUES ('[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}]');
INSERT INTO t_JsonExists_Case0006
  VALUES ('{
  "name":[{"first":"John"}, {"middle":"Mark"}, {"last":"Smith"}],
  "age":[{"John":"20"}, {"Mark":"35"}, {"Smith":"29"}]
}'); 
SELECT po.po_document FROM t_JsonExists_Case0006 po WHERE json_exists(po.po_document,'$[0][0]');
drop table t_JsonExists_Case0006;

\c regression
DROP DATABASE test_jsonpath_a;

-- jsonpath gram test
CREATE DATABASE test_jsonpath_pg dbcompatibility='PG';
\c test_jsonpath_pg
set behavior_compat_options='display_leading_zero';
select '1.type()'::jsonpath;
select '0755'::jsonpath;
select '00'::jsonpath;
select '"\b\f\r\n\t\v\"\''\\"'::jsonpath;
select '"\x50\u0067\u{53}\u{051}\u{00004C}"'::jsonpath;
select '$.foo\x50\u0067\u{53}\u{051}\u{00004C}\t\"bar'::jsonpath;
select '"\z"'::jsonpath;  -- unrecognized escape is just the literal char
select 'true'::jsonpath;
select 'false'::jsonpath;
select 'null'::jsonpath;
select '$a'::jsonpath;
select '$[true]'::jsonpath;
select 'strict $'::jsonpath;
select 'lax $'::jsonpath;
select '$.a.**.b'::jsonpath;
select '$.a.**{2}.b'::jsonpath;
select '$.a.**{2 to 2}.b'::jsonpath;
select '$.a.**{2 to 5}.b'::jsonpath;
select '$.a.**{0 to 5}.b'::jsonpath;
select '$.a.**{5 to last}.b'::jsonpath;
select '$.a.**{last}.b'::jsonpath;
select '$.a.**{last to 5}.b'::jsonpath;
select jsonpath_out('$.a.**{last to 5}.b');
select 'last'::jsonpath;
select '"last"'::jsonpath;
select '$.last'::jsonpath;
select '$[last]'::jsonpath;
select '$+1'::jsonpath;
select '$-1'::jsonpath;
select '$--+1'::jsonpath;
select '$.a/+-1'::jsonpath;
select jsonpath_out('$.a/+-1');
select '$.a[$a + 1, ($b[*]) to -($[0] * 2)]'::jsonpath;
select jsonpath_out('$.a[$a + 1, ($b[*]) to -($[0] * 2)]');
select '1 + ($.a.b + 2).c.d'::jsonpath;
select '($.a.b + -$.x.y).c.d'::jsonpath;
select '(-+$.a.b).c.d'::jsonpath;

select '$.g ? ($.a == 1)'::jsonpath;
select '$.g ? (@ == 1)'::jsonpath;
select '$.g ? (@.a == 1)'::jsonpath;
select '$.g ? (@.a == 1 || @.a == 4)'::jsonpath;
select '$.g ? (@.a == 1 && @.a == 4)'::jsonpath;
select '$.g ? (@.a == 1 || @.a == 4 && @.b == 7)'::jsonpath;
select '$.g ? (@.a == 1 || !(@.a == 4) && @.b == 7)'::jsonpath;
select '$.g ? (@.a == 1 || !(@.x >= 123 || @.a == 4) && @.b == 7)'::jsonpath;
select '$.g ? (@.x >= @[*]?(@.a > "abc"))'::jsonpath;
select jsonpath_out('$.g ? ((@.x >= 123 || @.a == 4) is unknown)');
select '$.g ? (exists (@.x))'::jsonpath;
select '$.g ? (exists (@.x ? (@ == 14)))'::jsonpath;
select '$.g ? ((@.x >= 123 || @.a == 4) && exists (@.x ? (@ == 14)))'::jsonpath;
select '$.g ? (+@.x >= +-(+@.a + 2))'::jsonpath;
select jsonpath_out('$.g ? (@.a <= 1 || !(@.x >= 123 || @.a < 4) && @.b == 7 && @.c > 7)');
select jsonpath_out('$ ? (@ starts with "abc")');
select jsonpath_out('$ ? (@ starts with $var)');
select '$ ? (@ like_regex "(invalid pattern")'::jsonpath;
select '$ ? (@ like_regex "pattern")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "i")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "is")'::jsonpath;
select jsonpath_out('$ ? (@ like_regex "pattern" flag "isim")');
select '$ ? (@ like_regex "pattern" flag "xsms")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "q")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "iq")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "smixq")'::jsonpath;
select '$ ? (@ like_regex "pattern" flag "a")'::jsonpath;
select '((($ + 1)).a + ((2)).b ? ((((@ > 1)) || (exists(@.c)))))'::jsonpath;
select '1.1.floor().ceiling().abs()'::jsonpath;
select '$.a[$.a.size() - 3]'::jsonpath;
select 'null.type()'::jsonpath;
select '1.type()'::jsonpath;
select '(1).type()'::jsonpath;
select '1.2.type()'::jsonpath;
select '"aaa".type()'::jsonpath;
select 'true.type()'::jsonpath;
select jsonpath_out('$.keyvalue().key');
select jsonpath_out('$.decimal(4,2)');
select '$.string()'::jsonpath;
select '$.double().floor().ceiling().abs()'::jsonpath;
select '$.boolean()'::jsonpath;
select '$.bigint().integer().number().decimal()'::jsonpath;
select jsonpath_out('$.date()');
select '$.datetime("datetime template")'::jsonpath;
select '$.time()'::jsonpath;
select '$.time_tz(4)'::jsonpath;
select '$.timestamp(2)'::jsonpath;
select '$.timestamp_tz(0)'::jsonpath;
\c regression
DROP DATABASE test_jsonpath_pg;