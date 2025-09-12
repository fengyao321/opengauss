set behavior_compat_options='compatible_a_db_array';

CREATE OR REPLACE TYPE num_type IS TABLE OF NUMBER;
CREATE OR REPLACE TYPE int_type IS TABLE OF INTEGER;
CREATE OR REPLACE TYPE char_type IS TABLE OF VARCHAR(20);

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

declare
  type num_type is table of int index by int;
  nt num_type := num_type();
begin
  nt(-1):=16;
  nt(-2):=87;
  nt(0):=13;
  nt(1):=11;
  nt(2):=22;
  nt(3):=33;
  nt(4):=44;

  nt.delete(-2,3);
  raise notice '%',nt(-2);
  raise notice '%',nt(-1);
  raise notice '%',nt(0);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
end;
/

declare
  type num_type is table of int index by int;
  nt num_type := num_type();
begin
  nt(-1):=16;
  nt(4):=44;
  nt(-2):=87;
  nt(1):=11;
  nt(0):=13;
  nt(2):=22;
  nt(3):=33;
  

  nt.delete(4,1);
  raise notice '%',nt(-2);
  raise notice '%',nt(-1);
  raise notice '%',nt(0);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
end;
/

declare
  type num_type is table of int index by int;
  nt num_type := num_type();
begin
  nt(-1):=16;
  nt(-2):=87;
  nt(0):=13;
  nt(1):=11;

  nt.delete(-5,3);
  raise notice '%',nt(-2);
  raise notice '%',nt(-1);
  raise notice '%',nt(0);
  raise notice '%',nt(1);
end;
/

DECLARE
  TYPE n1 IS varray(20) OF NUMBER;
  nt n1 := n1(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  TYPE n1 IS varray(20) OF NUMBER index by integer;
  nt n1 := n1(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

declare
    type ta is table of varchar(32) index by varchar(32);
    nt ta;
begin
    -- nt := array['red','orange','yellow','green'];
    nt('311') := 'yellow';
    nt(';') := 'red';
    nt('o2') := 'orange';
	raise notice '%',nt('311');
    raise notice '%',nt(';');
    raise notice '%',nt('o2');
    nt.DELETE(';');
    raise notice '%',nt('311');
    raise notice '%',nt(';');
    raise notice '%',nt('o2');
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE(2,3);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE(2,3);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt char_type := char_type('one', 'two', 'three', 'four', 'five', 'six');
BEGIN
  nt.DELETE(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt char_type := char_type('one', 'two', 'three', 'four', 'five', 'six');
BEGIN
  nt.DELETE(2,3);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE('1');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE('2','3');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE('1');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
BEGIN
  nt.DELETE('2','3');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt char_type := char_type('one', 'two', 'three', 'four', 'five', 'six');
BEGIN
  nt.DELETE('1');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt char_type := char_type('one', 'two', 'three', 'four', 'five', 'six');
BEGIN
  nt.DELETE('2','3');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
  idx int := 1;
BEGIN
  nt.DELETE(idx);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, end_idx);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, 3);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt num_type := num_type(11, 22, 33, 44, 55, 66);
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, '3');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
  idx int := 1;
BEGIN
  nt.DELETE(idx);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, end_idx);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, 3);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt int_type := int_type(11, 22, 33, 44, 55, 66);
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, '3');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

DECLARE
  nt char_type := char_type('one', 'two', 'three', 'four', 'five', 'six');
  start_idx int := 2;
  end_idx int := 3;
BEGIN
  nt.DELETE(start_idx, '3');
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
END;
/

declare
    type ta is table of varchar(32) index by integer;
    nt ta;
begin
    -- nt := array['red','orange','yellow','green'];
    nt(1) := 'red';
    nt(2) := 'orange';
    nt(3) := 'yellow';
    nt(4) := 'green';
    nt.DELETE(2);
    raise notice '%',nt(1);
    raise notice '%',nt(2);
    raise notice '%',nt(3);
    raise notice '%',nt(4);
END;
/

declare
    type ta is table of varchar(32) index by varchar(32);
    nt ta;
begin
    -- nt := array['red','orange','yellow','green'];
    nt('311') := 'yellow';
    nt('a11') := 'red';
    nt('o2') := 'orange';
    nt('aaa') := 'aadw';
    nt('4aw') := 'green';
    raise notice '%',nt('311');
    raise notice '%',nt('a11');
    raise notice '%',nt('o2');
    raise notice '%',nt('aaa');
    raise notice '%',nt('4aw');
    nt.DELETE('311');
    raise notice '%',nt('311');
    raise notice '%',nt('a11');
    raise notice '%',nt('o2');
    raise notice '%',nt('aaa');
    raise notice '%',nt('4aw');
END;
/

CREATE or REPLACE PROCEDURE proc1 AS
DECLARE
  type n1 is table of NUMBER;
  type nest_type is table of n1;
  nt nest_type;
BEGIN
  nt(1):=n1(1,2);
  nt(2):=n1(33, 44);
  nt(3):=n1(55, 66);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  nt.DELETE(2);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
END;
/
call proc1();
drop PROCEDURE if exists proc1;

create or replace procedure proc2 is
  type t1 is record(c1 int,c2 int);
  type t2 is table of t1;
  type t3 is varray(10) of t1;
  nt t3 := t3();
begin
  nt(1):=(5,6);
  nt(2):=(15,46);
  nt(3):=(35,76);
  nt(4):=(55,56);

  nt.delete(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
end;
/
call proc2();
drop PROCEDURE if exists proc2;

create or replace procedure proc3 is
  type t2 is table of int;
  type t1 is record(c1 int,c2 t2);
  type t3 is varray(10) of t1;
  nt t3 := t3();
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
begin
  nt(1):=(5,t2_0);
  nt(2):=(15,t2_1);
  nt(3):=(35,t2_2);
  nt(4):=(55,t2_0);

  nt.delete(1);
  raise notice '%',nt(1).c2;
  raise notice '%',nt(2).c2;
  raise notice '%',nt(3).c2;
  raise notice '%',nt(4).c2;
end;
/
call proc3();
drop PROCEDURE if exists proc3;

create or replace procedure proc4 is
  type t2 is table of int;
  type t1 is record(c1 int,c2 t2);
  type t3 is varray(10) of t1;
  nt t3 := t3();
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
begin
  nt(1):=(5,t2_0);
  nt(2):=(15,t2_1);
  nt(3):=(35,t2_2);
  nt(4):=(55,t2_0);

  nt.delete(1);
  raise notice '%',nt(1).c2;
  raise notice '%',nt(2).c2;
  raise notice '%',nt(3).c2;
  raise notice '%',nt(4).c2;
end;
/
call proc4();
drop PROCEDURE if exists proc4;

create or replace procedure proc5 is
  type t2 is table of int;
  type t1 is record(c1 int,c2 t2);
  type t3 is varray(10) of t1;
  nt t3 := t3();
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
begin
  nt(1):=(5,t2_0);
  nt(2):=(15,t2_1);
  nt(3):=(35,t2_2);
  nt(4):=(55,t2_0);

  nt.c2.delete(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
  raise notice '%',nt(4);
end;
/
call proc5();
drop PROCEDURE if exists proc5;

create or replace procedure proc6 is
  type t2 is table of int;
  type t1 is record(c1 int,c2 t2);
  type t3 is varray(10) of t1;
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
  nt t3 := t3((5,t2_0), (15,t2_1),(35,t2_2),(55,t2_0));
begin
  nt.delete(1);
  raise notice '%',nt(1).c2;
  raise notice '%',nt(2).c2;
  raise notice '%',nt(3).c2;
  raise notice '%',nt(4).c2;
end;
/
call proc6();
drop PROCEDURE if exists proc6;

create or replace procedure proc7 is
  type t2 is varray(10) of int;
  type t1 is varray(10) of t2;
  type t3 is varray(10) of t1;
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
  t2_3 t2 := t2(41,61);
  t2_4 t2 := t2(24,13);
  t2_5 t2 := t2(25,69);
  t1_1 t1 := t1(t2_0, t2_1);
  t1_2 t1 := t1(t2_2, t2_3);
  t1_3 t1 := t1(t2_4, t2_5);
  nt t3 := t3();
begin
  nt(1):= t1_1;
  nt(2):= t1_2;
  nt(3):= t1_3;
  nt.delete(1)(2);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
end;
/
call proc7();
drop PROCEDURE if exists proc7;

create or replace procedure proc8 is
  type t2 is varray(10) of int;
  type t1 is varray(10) of t2;
  type t3 is varray(10) of t1;
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
  t2_3 t2 := t2(41,61);
  t2_4 t2 := t2(24,13);
  t2_5 t2 := t2(25,69);
  t1_1 t1 := t1(t2_0, t2_1);
  t1_2 t1 := t1(t2_2, t2_3);
  t1_3 t1 := t1(t2_4, t2_5);
  nt t3 := t3();
begin
  nt(1):= t1_1;
  nt(2):= t1_2;
  nt(3):= t1_3;
  nt.delete(2);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
end;
/
call proc8();
drop PROCEDURE if exists proc8;

create or replace procedure proc9 is
  type t2 is varray(10) of int;
  type t1 is varray(10) of t2;
  type t3 is varray(10) of t1;
  t2_0 t2 := t2(4,6);
  t2_1 t2 := t2(14,16);
  t2_2 t2 := t2(15,66);
  t2_3 t2 := t2(41,61);
  t2_4 t2 := t2(24,13);
  t2_5 t2 := t2(25,69);
  t1_1 t1 := t1(t2_0, t2_1);
  t1_2 t1 := t1(t2_2, t2_3);
  t1_3 t1 := t1(t2_4, t2_5);
  nt t3 := t3();
begin
  nt(1):= t1_1;
  nt(2):= t1_2;
  nt(3):= t1_3;
  nt(2).delete(1);
  raise notice '%',nt(1);
  raise notice '%',nt(2);
  raise notice '%',nt(3);
end;
/
call proc9();
drop PROCEDURE if exists proc9;

DROP TYPE num_type;
DROP TYPE int_type;
DROP TYPE char_type;

create table test_nest_table(id serial,nt int);
declare
  type num_type is table of int;
  type nest_num_type is table of num_type;
  nt nest_num_type := nest_num_type();
  b int;
begin
  nt(1)(1):=11;
  nt(2)(1):=22;
  nt(3)(1):=33;
  nt(4)(1):=44;
  b :=10;

  raise notice '%',nt(1)(1);
  raise notice '%',nt(2)(1);
  raise notice '%',nt(3)(1);
  raise notice '%',nt(4)(1);
  raise notice '%',b;

  insert into test_nest_table(nt) values(nt(1)(1));
  insert into test_nest_table(nt) values(nt(2)(1));
  insert into test_nest_table(nt) values(nt(3)(1));
  insert into test_nest_table(nt) values(nt(4)(1));
  insert into test_nest_table(nt) values(b);
end;
/

select * from test_nest_table;
drop table test_nest_table;
