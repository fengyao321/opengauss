CREATE DATABASE test_jsonb_jsonpath_pg dbcompatibility='PG';
\c test_jsonb_jsonpath_pg

select jsonb_path_exists('{"a": 12}', '$');
select jsonb_path_exists('{"a": 12}', '1');
select jsonb_path_exists('{"a": 12}', '$.a.b');
select jsonb_path_exists('{"a": 12}', '$.b');

select jsonb_path_exists('{"a": {"a": 12}}', '$.a.a');
select jsonb_path_exists('{"a": {"a": 12}}', '$.*.a');
select jsonb_path_exists('{"b": {"a": 12}}', '$.*.a');
select jsonb_path_exists('{"b": {"a": 12}}', '$.*.b');
select jsonb_path_exists('{}', '$.*');
select jsonb_path_exists('{"a": 1}', '$.*');

select jsonb_path_exists('[]', '$[*]');
select jsonb_path_exists('[1]', '$[*]');
select jsonb_path_exists('[1]', '$[1]');

select jsonb_path_exists('[1]', '$[0]');
select jsonb_path_exists('[1]', '$[0.3]');
select jsonb_path_exists('[1]', '$[0.5]');
select jsonb_path_exists('[1]', '$[0.9]');
select jsonb_path_exists('[1]', '$[1.2]');
select jsonb_path_exists('{"a": [1,2,3], "b": [3,4,5]}', '$.*');
select jsonb_path_exists('{}', '$');

select jsonb_path_exists('[{"a": 1}, {"a": 2}, 3]', NULL);
select jsonb_path_exists(NULL, '$[1]');
select jsonb_path_exists('[{"a": 1}, {"a": 2}, 3]', '$[*]', NULL);

select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": 3}');
select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": -1}');
select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": 99}');
select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": "char"}');
select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": "char"}', silent => true);
select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '{"key": 3}');
select jsonb_path_exists('[0,1,2,3,4,5]', '$[$index]', vars => '"invalid vars"');

select jsonb_path_query_first('[{"a": 1}, {"a": 2}, 3]', NULL);
select jsonb_path_query_first(NULL, '$[1]');
select jsonb_path_query_first('[{"a": 1}, {"a": 2}, 3]', '$[*]', NULL);

select jsonb_path_query_first('{"a": 10}', '$');
select jsonb_path_query_first('{"a": 12, "b": {"a": 13}}', '$.a');
select jsonb_path_query_first('{"a": 12, "b": {"a": 13}}', '$.b');
select jsonb_path_query_first('{"a": 12, "b": {"a": 13}}', '$.*');

select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": 3}');
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": -1}');
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": 99}');
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index_from to $index_to]', vars => '{"index_from": 1, "index_to": 4}');
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": "char"}');
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '{"index": "char"}', silent => true);
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '{"key": 3}');
select jsonb_path_query_first('[0,1,2,3,4,5]', '$[$index]', vars => '"invalid vars"');

-- strict/lax
select jsonb_path_exists('[{"a": 1}, {"a": 2}, 3]', 'lax $[*].a', silent => false);
select jsonb_path_exists('[{"a": 1}, {"a": 2}, 3]', 'lax $[*].a', silent => true);
select jsonb_path_exists('[{"a": 1}, {"a": 2}, 3]', 'strict $[*].a', silent => false);
select jsonb_path_exists('[{"a": 1}, {"a": 2}, 3]', 'strict $[*].a', silent => true);
select jsonb_path_exists('{"b": {"a": 12}}', 'strict $.*.b');
select jsonb_path_exists('[1]', 'strict $[1]');
select jsonb_path_exists('[1]', 'lax $[10000000000000000]');
select jsonb_path_exists('[1]', 'strict $[10000000000000000]');

select jsonb_path_query_first('[1]', 'strict $[1]');
select jsonb_path_query_first('[1]', 'strict $[1]', silent => true);
select jsonb_path_query_first('[1]', 'lax $[10000000000000000]');
select jsonb_path_query_first('[1]', 'strict $[10000000000000000]');
select jsonb_path_query_first('1', 'lax $.a');
select jsonb_path_query_first('1', 'strict $.a');
select jsonb_path_query_first('1', 'strict $.*');
select jsonb_path_query_first('1', 'strict $.a', silent => true);
select jsonb_path_query_first('1', 'strict $.*', silent => true);
select jsonb_path_query_first('1', 'strict $[1]');
select jsonb_path_query_first('1', 'strict $[*]');
select jsonb_path_query_first('1', 'strict $[1]', silent => true);
select jsonb_path_query_first('1', 'strict $[*]', silent => true);
select jsonb_path_query_first('[]', 'lax $.a');
select jsonb_path_query_first('[]', 'strict $.a');
select jsonb_path_query_first('[]', 'strict $.a', silent => true);
select jsonb_path_query_first('[]', 'strict $[1]');
select jsonb_path_query_first('[]', 'strict $["a"]');
select jsonb_path_query_first('[]', 'strict $[1]', silent => true);
select jsonb_path_query_first('[]', 'strict $["a"]', silent => true);
select jsonb_path_query_first('{}', 'lax $.a');
select jsonb_path_query_first('{}', 'strict $.a');
select jsonb_path_query_first('{}', 'strict $.a', silent => true);
select jsonb_path_query_first('[1,2,3]', 'strict $[*].a');
select jsonb_path_query_first('[1,2,3]', 'strict $[*].a', silent => true);
select jsonb_path_query_first('[1,2,3,{"b": [3,4,5]}]', 'strict $.*');
select jsonb_path_query_first('[1,2,3,{"b": [3,4,5]}]', 'strict $.*', NULL, true);
select jsonb_path_query_first('[{"a": 1}, {"a": 2}, {}]', 'strict $[*].a');
select jsonb_path_query_first('[{"a": 1}, {"a": 2}, {}]', 'strict $[*].a', silent => true);

-- .**
select jsonb_path_exists('{"a": {"b": 1}}', 'lax $.**{1}');
select jsonb_path_exists('{"a": {"b": 1}}', 'lax $.**{2}');
select jsonb_path_exists('{"a": {"b": 1}}', 'lax $.**{3}');

select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{0}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{0 to last}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{1}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{1 to last}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{2}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{2 to last}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{3 to last}');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{last}');

-- last as array index
select jsonb_path_query_first('[]', '$[last]');
select jsonb_path_query_first('[]', 'strict $[last]');
select jsonb_path_query_first('[]', 'strict $[last]', silent => true);
select jsonb_path_query_first('[1]', '$[last]');
select jsonb_path_query_first('[1,2,3]', '$[last]');

-- arithmetic operators
select jsonb_path_exists('["1",2,0,3]', '-$[*]');
select jsonb_path_exists('[1,"2",0,3]', '-$[*]');
select jsonb_path_exists('["1",2,0,3]', 'strict -$[*]');
select jsonb_path_exists('[1,"2",0,3]', 'strict -$[*]');
select jsonb_path_exists('[1,"2",0,3]', 'strict -$[*]', silent => true);
select jsonb_path_query_first('{"a": 12}', '$.a + 2');
select jsonb_path_query_first('{"a": 12}', '$.b + 2');

select jsonb_path_query_first('0', '1 / $');
select jsonb_path_query_first('0', '1 / $ + 2');
select jsonb_path_query_first('0', '-(3 + 1 % $)');
select jsonb_path_query_first('1', '$ + "2"');
select jsonb_path_query_first('[1, 2]', '3 * $');
select jsonb_path_query_first('"a"', '-$');
select jsonb_path_query_first('[1,"2",3]', '+$');
select jsonb_path_query_first('1', '$ + "2"', silent => true);
select jsonb_path_query_first('[1, 2]', '3 * $', silent => true);
select jsonb_path_query_first('"a"', '-$', silent => true);
select jsonb_path_query_first('[1,"2",3]', '+$', silent => true);
select jsonb_path_query_first('[12, {"a": 13}, {"b": 14}]', 'lax $[0 to 10 / 0].a');

select jsonb_path_query_first('{"a": [2]}', 'lax $.a * 3');
select jsonb_path_query_first('{"a": [2]}', 'lax $.a + 3');
select jsonb_path_query_first('{"a": [7]}', 'lax $.a / 3');
select jsonb_path_query_first('{"a": [7]}', 'lax $.a % 3');
select jsonb_path_query_first('{"a": [2, 3, 4]}', 'lax -$.a');

select jsonb_path_query_first('{"a": [1, 2]}', 'lax $.a * 3');
select jsonb_path_query_first('{"a": [1, 2]}', 'lax $.a * 3', silent => true);

-- filter
select * from jsonb_path_query_first('{"a": 10}', '$ ? (@.a < $value)', '{"value" : 13}');
select * from jsonb_path_query_first('{"a": 10}', '$ ? (@.a < $value)', '{"value" : 8}');
select * from jsonb_path_query_first('[10,11,12,13,14,15]', '$[*] ? (@ < $value)', '{"value" : 13}');
select * from jsonb_path_query_first('[10,11,12,13,14,15]', '$[0,1] ? (@ < $x.value)', '{"x": {"value" : 13}}');
select * from jsonb_path_query_first('[1,"1",2,"2",null]', '$[*] ? (@ == "1")');
select * from jsonb_path_query_first('[1,"1",2,"2",null]', '$[*] ? (@ == $value)', '{"value" : "1"}');
select * from jsonb_path_query_first('[1,"1",2,"2",null]', '$[*] ? (@ == $value)', '{"value" : null}');
select * from jsonb_path_query_first('[1, "2", null]', '$[*] ? (@ != null)');
select * from jsonb_path_query_first('[1, "2", null]', '$[*] ? (@ == null)');
select * from jsonb_path_query_first('{}', '$ ? (@ == @)');
select * from jsonb_path_query_first('[]', 'strict $ ? (@ == @)');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{0}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{1}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{0 to last}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{1 to last}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"b": 1}}', 'lax $.**{1 to 2}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**{0}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**{1}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**{0 to last}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**{1 to last}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**{1 to 2}.b ? (@ > 0)');
select jsonb_path_query_first('{"a": {"c": {"b": 1}}}', 'lax $.**{2 to 3}.b ? (@ > 0)');

select jsonb_path_query_first('[]', '$[last ? (exists(last))]');
select jsonb_path_query_first('{"g": {"x": 2}}', '$.g ? (exists (@.x))');
select jsonb_path_query_first('{"g": {"x": 2}}', '$.g ? (exists (@.y))');
select jsonb_path_query_first('{"g": {"x": 2}}', '$.g ? (exists (@.x ? (@ >= 2) ))');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'lax $.g ? (exists (@.x))');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'lax $.g ? (exists (@.x + "3"))');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'lax $.g ? ((exists (@.x + "3")) is unknown)');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'strict $.g[*] ? (exists (@.x))');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'strict $.g[*] ? ((exists (@.x)) is unknown)');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'strict $.g ? (exists (@[*].x))');
select jsonb_path_query_first('{"g": [{"x": 2}, {"y": 3}]}', 'strict $.g ? ((exists (@[*].x)) is unknown)');
select jsonb_path_query_first('["", "a", "abc", "abcabc"]', '$[*] ? (@ starts with "abc")');
select jsonb_path_query_first('["", "a", "abc", "abcabc"]', 'strict $ ? (@[*] starts with "abc")');
select jsonb_path_query_first('["", "a", "abd", "abdabc"]', 'strict $ ? (@[*] starts with "abc")');
select jsonb_path_query_first('["abc", "abcabc", null, 1]', 'strict $ ? (@[*] starts with "abc")');
select jsonb_path_query_first('["abc", "abcabc", null, 1]', 'strict $ ? ((@[*] starts with "abc") is unknown)');
select jsonb_path_query_first('[[null, 1, "abc", "abcabc"]]', 'lax $ ? (@[*] starts with "abc")');
select jsonb_path_query_first('[[null, 1, "abd", "abdabc"]]', 'lax $ ? ((@[*] starts with "abc") is unknown)');
select jsonb_path_query_first('[null, 1, "abd", "abdabc"]', 'lax $[*] ? ((@ starts with "abc") is unknown)');
select jsonb_path_query_first('[null, 1, "abc", "abd", "aBdC", "abdacb", "babc", "adc\nabc", "ab\nadc"]', 'lax $[*] ? (@ like_regex "^ab.*c")');
select jsonb_path_query_first('[null, 1, "abc", "abd", "aBdC", "abdacb", "babc", "adc\nabc", "ab\nadc"]', 'lax $[*] ? (@ like_regex "^ab.*c" flag "i")');
select jsonb_path_query_first('[null, 1, "abc", "abd", "aBdC", "abdacb", "babc", "adc\nabc", "ab\nadc"]', 'lax $[*] ? (@ like_regex "^ab.*c" flag "m")');
select jsonb_path_query_first('[null, 1, "abc", "abd", "aBdC", "abdacb", "babc", "adc\nabc", "ab\nadc"]', 'lax $[*] ? (@ like_regex "^ab.*c" flag "s")');
select jsonb_path_query_first('[null, 1, "a\b", "a\\b", "^a\\b$"]', 'lax $[*] ? (@ like_regex "a\\b" flag "q")');
select jsonb_path_query_first('[null, 1, "a\b", "a\\b", "^a\\b$"]', 'lax $[*] ? (@ like_regex "a\\b" flag "")');
select jsonb_path_query_first('[null, 1, "a\b", "a\\b", "^a\\b$"]', 'lax $[*] ? (@ like_regex "^a\\b$" flag "q")');
select jsonb_path_query_first('[null, 1, "a\b", "a\\b", "^a\\b$"]', 'lax $[*] ? (@ like_regex "^a\\B$" flag "q")');
select jsonb_path_query_first('[null, 1, "a\b", "a\\b", "^a\\b$"]', 'lax $[*] ? (@ like_regex "^a\\B$" flag "iq")');
select jsonb_path_query_first('[null, 1, "a\b", "a\\b", "^a\\b$"]', 'lax $[*] ? (@ like_regex "^a\\b$" flag "")');

select jsonb_path_query_first('{"c": {"a": 2, "b":1}}', '$.** ? (@.a == 1 + 1)');
select jsonb_path_query_first('{"c": {"a": 2, "b":1}}', '$.** ? (@.a == (1 + 1))');
select jsonb_path_query_first('{"c": {"a": 2, "b":1}}', '$.** ? (@.a == @.b + 1)');
select jsonb_path_query_first('{"c": {"a": 2, "b":1}}', '$.** ? (@.a == (@.b + 1))');
select jsonb_path_query_first('[1, 2, 3]', '($[*] > 2) ? (@ == true)');
SELECT jsonb_path_query_first('[{"a": 1}, {"a": 2}, {"a": 3}, {"a": 5}]', '$[*].a ? (@ > $min && @ < $max)', vars => '{"min": 1, "max": 4}');
SELECT jsonb_path_query_first('[{"a": 1}, {"a": 2}, {"a": 3}, {"a": 5}]', '$[*].a ? (@ > $min && @ < $max)', vars => '{"min": 3, "max": 4}');

-- methods
select jsonb_path_query_first('{"a": 2}', '($.a - 5).abs() + 10');
select jsonb_path_query_first('{"a": 2.5}', '-($.a * $.a).floor() % 4.3');
select jsonb_path_query_first('[1, 2, 3]', '($[*] > 3).type()');
select jsonb_path_query_first('[1, 2, 3]', '($[*].a > 3).type()');
select jsonb_path_query_first('[1, 2, 3]', 'strict ($[*].a > 3).type()');
select jsonb_path_query_first('[0, 1, -2, -3.4, 5.6]', '$[*].abs()');
select jsonb_path_query_first('[0, 1, -2, -3.4, 5.6]', '$[*].floor()');
select jsonb_path_query_first('[0, 1, -2, -3.4, 5.6]', '$[*].ceiling()');
select jsonb_path_query_first('[0, 1, -2, -3.4, 5.6]', '$[*].ceiling().abs()');
select jsonb_path_query_first('[0, 1, -2, -3.4, 5.6]', '$[*].ceiling().abs().type()');
select jsonb_path_query_first('{}', '$.abs()');
select jsonb_path_query_first('true', '$.floor()');
select jsonb_path_query_first('"1.2"', '$.ceiling()');
select jsonb_path_query_first('{}', '$.abs()', silent => true);
select jsonb_path_query_first('true', '$.floor()', silent => true);
select jsonb_path_query_first('"1.2"', '$.ceiling()', silent => true);
select jsonb_path_query_first('[12, {"a": 13}, {"b": 14}, "ccc", true]', '$[2.5 - 1 to $.size() - 2]');
select jsonb_path_query_first('[1,null,true,"11",[],[1],[1,2,3],{},{"a":1,"b":2}]', 'strict $[*].size()');
select jsonb_path_query_first('[1,null,true,"11",[],[1],[1,2,3],{},{"a":1,"b":2}]', 'strict $[*].size()', silent => true);
select jsonb_path_query_first('[1,null,true,"11",[],[1],[1,2,3],{},{"a":1,"b":2}]', 'lax $[*].size()');
select jsonb_path_query_first('[1,2,3]', '$[last ? (@.type() == "number")]');
select jsonb_path_query_first('[1,2,3]', '$[last ? (@.type() == "string")]');
select jsonb_path_query_first('[1,2,3]', '$[last ? (@.type() == "string")]', silent => true);
select jsonb_path_query_first('[null,1,true,"a",[],{}]', '$.type()');
select jsonb_path_query_first('[null,1,true,"a",[],{}]', 'lax $.type()');
select jsonb_path_query_first('[null,1,true,"a",[],{}]', '$[*].type()');
select jsonb_path_query_first('null', 'null.type()');
select jsonb_path_query_first('null', 'true.type()');
select jsonb_path_query_first('null', '(123).type()');
select jsonb_path_query_first('null', '"123".type()');
select jsonb_path_query_first('[{},1]', '$[*].keyvalue()');
select jsonb_path_query_first('[{},1]', '$[*].keyvalue()', silent => true);
select jsonb_path_query_first('{}', '$.keyvalue()');
select jsonb_path_query_first('{"a": 1, "b": [1, 2], "c": {"a": "bbb"}}', '$.keyvalue()');
select jsonb_path_query_first('[{"a": 1, "b": [1, 2]}, {"c": {"a": "bbb"}}]', '$[*].keyvalue()');
select jsonb_path_query_first('[{"a": 1, "b": [1, 2]}, {"c": {"a": "bbb"}}]', 'strict $.keyvalue()');
select jsonb_path_query_first('[{"a": 1, "b": [1, 2]}, {"c": {"a": "bbb"}}]', 'lax $.keyvalue()');
select jsonb_path_query_first('[{"a": 1, "b": [1, 2]}, {"c": {"a": "bbb"}}]', 'strict $.keyvalue().a');
select jsonb_path_exists('{"a": 1, "b": [1, 2]}', 'lax $.keyvalue()');
select jsonb_path_exists('{"a": 1, "b": [1, 2]}', 'lax $.keyvalue().key');

-- .string()
select jsonb_path_query_first('null', '$.string()');
select jsonb_path_query_first('null', '$.string()', silent => true);
select jsonb_path_query_first('[]', '$.string()');
select jsonb_path_query_first('[]', 'strict $.string()');
select jsonb_path_query_first('{}', '$.string()');
select jsonb_path_query_first('[]', 'strict $.string()', silent => true);
select jsonb_path_query_first('{}', '$.string()', silent => true);
select jsonb_path_query_first('"1.23"', '$.string()');
select jsonb_path_query_first('"1.23aaa"', '$.string()');
select jsonb_path_query_first('true', '$.string()');
select jsonb_path_query_first('1234', '$.string().type()');
select jsonb_path_query_first('[2, true]', '$.string()');
select jsonb_path_query_first('[1.23, "yes", false]', '$[*].string().type()');

-- time type, not supported
select jsonb_path_exists('"10-03-2017"', '$.datetime("dd-mm-yyyy")');
select jsonb_path_exists('"2023-08-15"', '$.date()');
select jsonb_path_exists('"12:34:56"', '$.time()');
select jsonb_path_exists('"12:34:56 +05:30"', '$.time_tz()');
select jsonb_path_exists('"2023-08-15 12:34:56"', '$.timestamp()');
select jsonb_path_exists('"2023-08-15 12:34:56 +05:30"', '$.timestamp_tz()');

-- Test .number()
select jsonb_path_query_first('null', '$.number()');
select jsonb_path_query_first('true', '$.number()');
select jsonb_path_query_first('true', '$.number()', silent => true);
select jsonb_path_query_first('[]', '$.number()');
select jsonb_path_query_first('[]', 'strict $.number()');
select jsonb_path_query_first('{}', '$.number()');
select jsonb_path_query_first('[]', 'strict $.number()', silent => true);
select jsonb_path_query_first('{}', '$.number()', silent => true);
select jsonb_path_query_first('1.23', '$.number()');
select jsonb_path_query_first('"1.23"', '$.number()');
select jsonb_path_query_first('"1.23aaa"', '$.number()');
select jsonb_path_query_first('1e1000', '$.number()');
select jsonb_path_query_first('"nan"', '$.number()');
select jsonb_path_query_first('"NaN"', '$.number()');
select jsonb_path_query_first('"inf"', '$.number()');
select jsonb_path_query_first('"-inf"', '$.number()');
select jsonb_path_query_first('"inf"', '$.number()', silent => true);
select jsonb_path_query_first('"-inf"', '$.number()', silent => true);
select jsonb_path_query_first('123', '$.number()');
select jsonb_path_query_first('"123"', '$.number()');
select jsonb_path_query_first('12345678901234567890', '$.number()');
select jsonb_path_query_first('"12345678901234567890"', '$.number()');
select jsonb_path_query_first('"+12.3"', '$.number()');
select jsonb_path_query_first('-12.3', '$.number()');
select jsonb_path_query_first('"-12.3"', '$.number()');
select jsonb_path_query_first('12.3', '$.number() * 2');

-- Test .decimal()
select jsonb_path_query_first('null', '$.decimal()');
select jsonb_path_query_first('true', '$.decimal()');
select jsonb_path_query_first('null', '$.decimal()', silent => true);
select jsonb_path_query_first('true', '$.decimal()', silent => true);
select jsonb_path_query_first('[]', '$.decimal()');
select jsonb_path_query_first('[]', 'strict $.decimal()');
select jsonb_path_query_first('{}', '$.decimal()');
select jsonb_path_query_first('[]', 'strict $.decimal()', silent => true);
select jsonb_path_query_first('{}', '$.decimal()', silent => true);
select jsonb_path_query_first('1.23', '$.decimal()');
select jsonb_path_query_first('"1.23"', '$.decimal()');
select jsonb_path_query_first('"1.23aaa"', '$.decimal()');
select jsonb_path_query_first('1e1000', '$.decimal()');
select jsonb_path_query_first('"nan"', '$.decimal()');
select jsonb_path_query_first('"NaN"', '$.decimal()');
select jsonb_path_query_first('"inf"', '$.decimal()');
select jsonb_path_query_first('"-inf"', '$.decimal()');
select jsonb_path_query_first('"inf"', '$.decimal()', silent => true);
select jsonb_path_query_first('"-inf"', '$.decimal()', silent => true);
select jsonb_path_query_first('123', '$.decimal()');
select jsonb_path_query_first('"123"', '$.decimal()');
select jsonb_path_query_first('12345678901234567890', '$.decimal()');
select jsonb_path_query_first('"12345678901234567890"', '$.decimal()');
select jsonb_path_query_first('"+12.3"', '$.decimal()');
select jsonb_path_query_first('-12.3', '$.decimal()');
select jsonb_path_query_first('"-12.3"', '$.decimal()');
select jsonb_path_query_first('12.3', '$.decimal() * 2');
select jsonb_path_query_first('12345.678', '$.decimal(6, 1)');
select jsonb_path_query_first('12345.678', '$.decimal(6, 2)');
select jsonb_path_query_first('1234.5678', '$.decimal(6, 2)');
select jsonb_path_query_first('12345.678', '$.decimal(7, 6)');
select jsonb_path_query_first('12345.678', '$.decimal(0, 6)');
select jsonb_path_query_first('12345.678', '$.decimal(1001, 6)');
select jsonb_path_query_first('1234.5678', '$.decimal(-6, +2)');
select jsonb_path_query_first('1234.5678', '$.decimal(6, -1001)');
select jsonb_path_query_first('0.0123456', '$.decimal(3,2)');
select jsonb_path_query_first('0.0012345', '$.decimal(6,4)');
select jsonb_path_query_first('12.3', '$.decimal(12345678901,1)');
select jsonb_path_query_first('12.3', '$.decimal(1,12345678901)');

-- double
select jsonb_path_query_first('null', '$.double()');
select jsonb_path_query_first('true', '$.double()');
select jsonb_path_query_first('null', '$.double()', silent => true);
select jsonb_path_query_first('true', '$.double()', silent => true);
select jsonb_path_query_first('[]', '$.double()');
select jsonb_path_query_first('[]', 'strict $.double()');
select jsonb_path_query_first('{}', '$.double()');
select jsonb_path_query_first('[]', 'strict $.double()', silent => true);
select jsonb_path_query_first('{}', '$.double()', silent => true);
select jsonb_path_query_first('1.23', '$.double()');
select jsonb_path_query_first('"1.23"', '$.double()');
select jsonb_path_query_first('"1.23aaa"', '$.double()');
select jsonb_path_query_first('1e1000', '$.double()');
select jsonb_path_query_first('"nan"', '$.double()');
select jsonb_path_query_first('"NaN"', '$.double()');
select jsonb_path_query_first('"inf"', '$.double()');
select jsonb_path_query_first('"-inf"', '$.double()');
select jsonb_path_query_first('"inf"', '$.double()', silent => true);
select jsonb_path_query_first('"-inf"', '$.double()', silent => true);

-- .boolean()
select jsonb_path_query_first('null', '$.boolean()');
select jsonb_path_query_first('null', '$.boolean()', silent => true);
select jsonb_path_query_first('[]', '$.boolean()');
select jsonb_path_query_first('[]', 'strict $.boolean()');
select jsonb_path_query_first('{}', '$.boolean()');
select jsonb_path_query_first('[]', 'strict $.boolean()', silent => true);
select jsonb_path_query_first('{}', '$.boolean()', silent => true);
select jsonb_path_query_first('1.23', '$.boolean()');
select jsonb_path_query_first('"1.23"', '$.boolean()');
select jsonb_path_query_first('"1.23aaa"', '$.boolean()');
select jsonb_path_query_first('1e1000', '$.boolean()');
select jsonb_path_query_first('"nan"', '$.boolean()');
select jsonb_path_query_first('"NaN"', '$.boolean()');
select jsonb_path_query_first('"inf"', '$.boolean()');
select jsonb_path_query_first('"-inf"', '$.boolean()');
select jsonb_path_query_first('"inf"', '$.boolean()', silent => true);
select jsonb_path_query_first('"-inf"', '$.boolean()', silent => true);
select jsonb_path_query_first('"100"', '$.boolean()');
select jsonb_path_query_first('true', '$.boolean()');
select jsonb_path_query_first('false', '$.boolean()');
select jsonb_path_query_first('1', '$.boolean()');
select jsonb_path_query_first('0', '$.boolean()');
select jsonb_path_query_first('-1', '$.boolean()');
select jsonb_path_query_first('100', '$.boolean()');
select jsonb_path_query_first('"1"', '$.boolean()');
select jsonb_path_query_first('"0"', '$.boolean()');
select jsonb_path_query_first('"true"', '$.boolean()');
select jsonb_path_query_first('"false"', '$.boolean()');
select jsonb_path_query_first('"TRUE"', '$.boolean()');
select jsonb_path_query_first('"FALSE"', '$.boolean()');
select jsonb_path_query_first('"yes"', '$.boolean()');
select jsonb_path_query_first('"NO"', '$.boolean()');
select jsonb_path_query_first('"T"', '$.boolean()');
select jsonb_path_query_first('"f"', '$.boolean()');
select jsonb_path_query_first('"y"', '$.boolean()');
select jsonb_path_query_first('"N"', '$.boolean()');
select jsonb_path_query_first('true', '$.boolean().type()');
select jsonb_path_query_first('123', '$.boolean().type()');
select jsonb_path_query_first('"Yes"', '$.boolean().type()');
select jsonb_path_query_first('[1, "yes", false]', '$[*].boolean()');

-- Test .integer()
select jsonb_path_query_first('null', '$.integer()');
select jsonb_path_query_first('true', '$.integer()');
select jsonb_path_query_first('null', '$.integer()', silent => true);
select jsonb_path_query_first('true', '$.integer()', silent => true);
select jsonb_path_query_first('[]', '$.integer()');
select jsonb_path_query_first('[]', 'strict $.integer()');
select jsonb_path_query_first('{}', '$.integer()');
select jsonb_path_query_first('[]', 'strict $.integer()', silent => true);
select jsonb_path_query_first('{}', '$.integer()', silent => true);
select jsonb_path_query_first('"1.23"', '$.integer()');
select jsonb_path_query_first('"1.23aaa"', '$.integer()');
select jsonb_path_query_first('1e1000', '$.integer()');
select jsonb_path_query_first('"nan"', '$.integer()');
select jsonb_path_query_first('"NaN"', '$.integer()');
select jsonb_path_query_first('"inf"', '$.integer()');
select jsonb_path_query_first('"-inf"', '$.integer()');
select jsonb_path_query_first('"inf"', '$.integer()', silent => true);
select jsonb_path_query_first('"-inf"', '$.integer()', silent => true);
select jsonb_path_query_first('123', '$.integer()');
select jsonb_path_query_first('"123"', '$.integer()');
select jsonb_path_query_first('1.23', '$.integer()');
select jsonb_path_query_first('1.83', '$.integer()');
select jsonb_path_query_first('12345678901', '$.integer()');
select jsonb_path_query_first('"12345678901"', '$.integer()');
select jsonb_path_query_first('"+123"', '$.integer()');
select jsonb_path_query_first('-123', '$.integer()');
select jsonb_path_query_first('"-123"', '$.integer()');
select jsonb_path_query_first('123', '$.integer() * 2');

-- Test .bigint()
select jsonb_path_query_first('null', '$.bigint()');
select jsonb_path_query_first('true', '$.bigint()');
select jsonb_path_query_first('null', '$.bigint()', silent => true);
select jsonb_path_query_first('true', '$.bigint()', silent => true);
select jsonb_path_query_first('[]', '$.bigint()');
select jsonb_path_query_first('[]', 'strict $.bigint()');
select jsonb_path_query_first('{}', '$.bigint()');
select jsonb_path_query_first('[]', 'strict $.bigint()', silent => true);
select jsonb_path_query_first('{}', '$.bigint()', silent => true);
select jsonb_path_query_first('"1.23"', '$.bigint()');
select jsonb_path_query_first('"1.23aaa"', '$.bigint()');
select jsonb_path_query_first('1e1000', '$.bigint()');
select jsonb_path_query_first('"nan"', '$.bigint()');
select jsonb_path_query_first('"NaN"', '$.bigint()');
select jsonb_path_query_first('"inf"', '$.bigint()');
select jsonb_path_query_first('"-inf"', '$.bigint()');
select jsonb_path_query_first('"inf"', '$.bigint()', silent => true);
select jsonb_path_query_first('"-inf"', '$.bigint()', silent => true);
select jsonb_path_query_first('123', '$.bigint()');
select jsonb_path_query_first('"123"', '$.bigint()');
select jsonb_path_query_first('1.23', '$.bigint()');
select jsonb_path_query_first('1.83', '$.bigint()');
select jsonb_path_query_first('1234567890123', '$.bigint()');
select jsonb_path_query_first('"1234567890123"', '$.bigint()');
select jsonb_path_query_first('12345678901234567890', '$.bigint()');
select jsonb_path_query_first('"12345678901234567890"', '$.bigint()');
select jsonb_path_query_first('"+123"', '$.bigint()');
select jsonb_path_query_first('-123', '$.bigint()');
select jsonb_path_query_first('"-123"', '$.bigint()');
select jsonb_path_query_first('123', '$.bigint() * 2');

\c regression
DROP DATABASE test_jsonb_jsonpath_pg;