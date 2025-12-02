create schema alter_sequence;
set current_schema = alter_sequence;

create table identity_t1(id int IDENTITY, bookname NVARCHAR(50), author NVARCHAR(50));
create sequence s1;
-- alter sequence name not supported
alter sequence identity_t1_id_seq_identity rename to identity_t1_id_seq_identity1;
alter sequence s1 rename to s2;

drop schema alter_sequence cascade;
