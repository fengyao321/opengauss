drop schema if exists test_views3 cascade;
create schema test_views3;
set current_schema to test_views3;

-- sys.triggers
\d sys.triggers

-- sys.trigger_events
\d sys.trigger_events

-- dml trigger
create table animals (id int, name char(30));
create table food (id int, foodtype varchar(32), remark varchar(32));

create or replace function insert_food_fun returns trigger as
$$
begin
    insert into food(id, foodtype, remark) values (1, 'bamboo', 'healthy');
    RAISE NOTICE 'insert_food_fun';
    return NEW;
end;
$$ language plpgsql;

create trigger animals_trigger_after after insert on animals
for each row
execute procedure insert_food_fun();

insert into animals values('1', 'panda');
select * from food;

select name, parent_class, parent_class_desc, type, type_desc, create_date, modify_date, 
  is_ms_shipped, is_disabled, is_not_for_replication, is_instead_of_trigger from sys.triggers
  where name = 'animals_trigger_after';

select count(*) from sys.triggers tr inner join pg_trigger pt on tr.object_id = pt.oid
  and tr.name = pt.tgname where tr.name = 'animals_trigger_after';

select count(*) from sys.triggers tr inner join pg_trigger pt on tr.object_id = pt.oid
  and tr.name = pt.tgname and tr.parent_id = pt.tgrelid where tr.name = 'animals_trigger_after';

create trigger animals_trigger_before before insert on animals
for each row
execute procedure insert_food_fun();

select name, parent_class, parent_class_desc, type, type_desc, create_date, modify_date, 
  is_ms_shipped, is_disabled, is_not_for_replication, is_instead_of_trigger from sys.triggers
  where name = 'animals_trigger_before';

select count(*) from sys.triggers tr inner join pg_trigger pt on tr.object_id = pt.oid
  and tr.name = pt.tgname where tr.name = 'animals_trigger_before';

select count(*) from sys.triggers tr inner join pg_trigger pt on tr.object_id = pt.oid
  and tr.name = pt.tgname and tr.parent_id = pt.tgrelid where tr.name = 'animals_trigger_before';

create view view_animals as select * from animals;

create trigger animals_trigger_instead instead of insert on view_animals
for each row
execute procedure insert_food_fun();

select name, parent_class, parent_class_desc, type, type_desc, create_date, modify_date, 
  is_ms_shipped, is_disabled, is_not_for_replication, is_instead_of_trigger from sys.triggers
  where name = 'animals_trigger_instead';

select count(*) from sys.triggers tr inner join pg_trigger pt on tr.object_id = pt.oid
  and tr.name = pt.tgname where tr.name = 'animals_trigger_instead';

select count(*) from sys.triggers tr inner join pg_trigger pt on tr.object_id = pt.oid
  and tr.name = pt.tgname and tr.parent_id = pt.tgrelid where tr.name = 'animals_trigger_instead';

select name, is_instead_of_trigger from sys.triggers where name like 'animals_trigger%' order by name;

alter table animals disable trigger animals_trigger_after;
select tgenabled from pg_trigger where tgname = 'animals_trigger_after';
select is_disabled from sys.triggers where name = 'animals_trigger_after';

alter table animals enable trigger animals_trigger_after;
select tgenabled from pg_trigger where tgname = 'animals_trigger_after';
select is_disabled from sys.triggers where name = 'animals_trigger_after';

select pt.tgname, type, type_desc, is_first, is_last, event_group_type, event_group_type_desc, is_trigger_event
  from sys.trigger_events tr inner join pg_trigger pt on tr.object_id = pt.oid order by pt.tgname, type;

create trigger animals_trigger_after_insert after insert on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_after_delete after delete on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_after_update after update on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_after_truncate after truncate on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_after_mix after insert or delete or update on animals
for each row
execute procedure insert_food_fun();

create trigger animals_trigger_before_insert before insert on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_before_delete before delete on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_before_update before update on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_before_truncate before truncate on animals
for each statement
execute procedure insert_food_fun();

create trigger animals_trigger_before_mix before insert or delete or update on animals
for each row
execute procedure insert_food_fun();

select pt.tgname, type, type_desc, is_first, is_last, event_group_type, event_group_type_desc, is_trigger_event
  from sys.trigger_events tr inner join pg_trigger pt on tr.object_id = pt.oid order by pt.tgname, type;

select name, is_instead_of_trigger from sys.triggers where name like 'animals_trigger%' order by name;

-- event trigger
create or replace function drop_sql_command()
returns event_trigger as $$
begin
    raise notice '% - sql_drop', tg_tag;
end;
$$ language plpgsql;

create or replace function test_evtrig_no_rewrite() returns event_trigger
language plpgsql as $$
begin
    raise exception 'rewrites not allowed';
end;
$$;

create function test_event_trigger() returns event_trigger as $$
begin
    raise notice 'test_event_trigger: % %', tg_event, tg_tag;
end
$$ language plpgsql;

create event trigger regress_event_trigger on ddl_command_start
  execute procedure test_event_trigger();

create event trigger regress_event_trigger_end on ddl_command_end
  execute procedure test_event_trigger();

create event trigger sql_drop_command ON sql_drop
  execute procedure drop_sql_command();

create event trigger no_rewrite_allowed on table_rewrite
  when tag in ('alter table') execute procedure test_evtrig_no_rewrite();

create table event_trigger_table (a int);

alter table event_trigger_table alter column a type numeric; --error, rewrites not allowed

drop table event_trigger_table;

select name, parent_class, parent_class_desc, parent_id, type, type_desc, create_date, modify_date, 
  is_ms_shipped, is_disabled, is_not_for_replication, is_instead_of_trigger from sys.triggers
  where parent_class = 0;

select pet.evtname, type, type_desc, is_first, is_last, event_group_type, event_group_type_desc, is_trigger_event
  from sys.trigger_events tr inner join pg_event_trigger pet on tr.object_id = pet.oid;

create role regress_evt_user with encrypted password 'EvtUser123';
alter event trigger regress_event_trigger rename to regress_event_trigger_start;
alter event trigger regress_event_trigger_start owner to regress_evt_user; -- error, only superuser allowed

alter event trigger regress_event_trigger_start disable;
select evtenabled from pg_event_trigger where evtname = 'regress_event_trigger_start';
select is_disabled from sys.triggers where name = 'regress_event_trigger_start';

create table event_trigger_table1 (a int);

alter event trigger regress_event_trigger_start enable always;
select evtenabled from pg_event_trigger where evtname = 'regress_event_trigger_start';
select is_disabled from sys.triggers where name = 'regress_event_trigger_start';

create table event_trigger_table2 (a int);

drop event trigger regress_event_trigger_start;
drop event trigger regress_event_trigger_end;
drop event trigger sql_drop_command;
drop event trigger no_rewrite_allowed;

drop schema test_views3 cascade;