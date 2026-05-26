\echo Use "CREATE EXTENSION gv_index" to load this file. \quit

CREATE OR REPLACE FUNCTION gv_graph_index_handler(internal) RETURNS index_am_handler
    AS 'MODULE_PATHNAME' LANGUAGE C;
DROP ACCESS METHOD IF EXISTS gv_graph;
CREATE ACCESS METHOD gv_graph TYPE INDEX HANDLER gv_graph_index_handler;

CREATE OPERATOR CLASS vector_l2_ops
    FOR TYPE vector USING gv_graph AS
    OPERATOR 1 <-> (vector, vector) FOR ORDER BY float_ops,
    FUNCTION 1 vector_l2_squared_distance(vector, vector);

CREATE OPERATOR CLASS vector_cosine_ops
    FOR TYPE vector USING gv_graph AS
    OPERATOR 1 <+> (vector, vector) FOR ORDER BY float_ops,
    FUNCTION 1 vector_negative_inner_product(vector, vector),
    FUNCTION 2 vector_norm(vector);