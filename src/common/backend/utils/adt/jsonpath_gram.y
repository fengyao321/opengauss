%{
/*-------------------------------------------------------------------------
 *
 * jsonpath_gram.y
 *     Grammar definitions for jsonpath datatype
 *
 * Transforms tokenized jsonpath into tree of JsonPathParseItem structs.
 *
 * Portions Copyright (c) 2026 Huawei Technologies Co.,Ltd.
 * Copyright (c) 2019-2025, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *    src/common/backend/utils/adt/jsonpath_gram.y
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "catalog/pg_collation.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "nodes/pg_list.h"
#include "parser/scanner.h"
#include "regex/regex.h"
#include "utils/builtins.h"
#include "utils/jsonpath.h"

static JsonPathParseItem *makeItemType(JsonPathItemType type);
static JsonPathParseItem *makeItemString(JsonPathString *s);
static JsonPathParseItem *makeItemKey(JsonPathString *s);
static JsonPathParseItem *makeItemNumeric(JsonPathString *s);
static JsonPathParseItem *makeItemBool(bool val);
static JsonPathParseItem *makeItemBinary(JsonPathItemType type,
                                         JsonPathParseItem *la,
                                         JsonPathParseItem *ra);
static JsonPathParseItem *makeItemList(List *list);
static JsonPathParseItem *makeIndexArray(List *list);
static JsonPathParseItem * makeItemVariable(JsonPathString *s);
static JsonPathParseItem *makeAny(int first, int last);
static JsonPathParseItem *makeItemUnary(JsonPathItemType type,
                                        JsonPathParseItem *a);
static bool makeItemLikeRegex(JsonPathParseItem *expr,
                              JsonPathString *pattern,
                              JsonPathString *flags,
                              JsonPathParseItem ** result);

static void checkAFormatIndex(JsonPathParseItem* item);

/*
 * Bison doesn't allocate anything that needs to live across parser calls,
 * so we can easily have it use palloc instead of malloc.  This prevents
 * memory leaks if we error out during parsing.
 */
#define YYMALLOC palloc
#define YYFREE   pfree

#define YY_DECL extern int     jsonpath_yylex(YYSTYPE *yylval_param, \
                              JsonPathParseResult **result)
YY_DECL;

static void
jsonpath_yyerror(const char *message);
#define yyerror(result, escontext, msg) jsonpath_yyerror(msg)

%}

/* BISON Declarations */
%define api.pure
%expect 0
%name-prefix="jsonpath_yy"
%parse-param {JsonPathParseResult **result}
%parse-param {struct Node *escontext}
%lex-param {JsonPathParseResult **result}

%union
{
    JsonPathString        str;
    List               *elems;    /* list of JsonPathParseItem */
    List               *indexs;    /* list of integers */
    JsonPathParseItem  *value;
    JsonPathParseResult *result;
    JsonPathItemType    optype;
    bool                boolean;
    int                    integer;
}

%token    <str>        TO_P NULL_P TRUE_P FALSE_P STRICT_P LAX_P
%token    <str>        IDENT_P STRING_P NUMERIC_P INT_P VARIABLE_P
%token    <str>        LESS_P LESSEQUAL_P EQUAL_P NOTEQUAL_P GREATEREQUAL_P GREATER_P
%token    <str>        IS_P UNKNOWN_P EXISTS_P STARTS_P WITH_P LIKE_REGEX_P FLAG_P
%token    <str>        OR_P AND_P NOT_P
%token    <str>        ABS_P SIZE_P TYPE_P CEILING_P FLOOR_P KEYVALUE_P
%token    <str>        TIME_P TIME_TZ_P TIMESTAMP_P TIMESTAMP_TZ_P DATE_P DATETIME_P
%token    <str>        STRINGFUNC_P NUMBER_P DECIMAL_P BIGINT_P INTEGER_P
%token    <str>        DOUBLE_P BOOLEAN_P
%token    <str>        ANY_P LAST_P
%type    <result>    result

%type    <value>        scalar_value path_primary expr array_accessor
                    any_path accessor_op key index_elem expr_or_predicate
                    predicate delimited_predicate starts_with_initial
                    datetime_template opt_datetime_template csv_elem
                    datetime_precision opt_datetime_precision

%type    <elems>        accessor_expr  csv_list opt_csv_list
%type    <integer>      any_level
%type    <indexs>    index_list
%type    <boolean>    mode
%type    <str>        key_name
%type    <optype>     comp_op method

%left    OR_P
%left    AND_P
%right    NOT_P
%left    '+' '-'
%left    '*' '/' '%'
%left    UMINUS
%nonassoc '(' ')'

/* Grammar follows */
%%

result:
    mode expr_or_predicate            {
                                        *result = (JsonPathParseResult*)palloc(sizeof(JsonPathParseResult));
                                        (*result)->expr = $2;
                                        (*result)->lax = $1;
                                        (void) yynerrs;
                                 }
    | /* EMPTY */                    { *result = NULL; }
    ;

expr_or_predicate:
    expr                            { $$ = $1; }
    | predicate                        { $$ = $1; }
    ;

mode:
    STRICT_P                        
    {
        if (DB_IS_CMPT(A_FORMAT)) {
            ereport(ERROR,
                    (errcode(ERRCODE_SYNTAX_ERROR),
                        errmsg("invalid input syntax for type %s", "jsonpath"),
                        errdetail("specifying strict/lax mode is not supported "
                            "in A_FORMAT database")));
        }
        $$ = false;
    }
    | LAX_P                            
    {
        if (DB_IS_CMPT(A_FORMAT)) {
            ereport(ERROR,
                    (errcode(ERRCODE_SYNTAX_ERROR),
                        errmsg("invalid input syntax for type %s", "jsonpath"),
                        errdetail("specifying strict/lax mode is not supported "
                            "in A_FORMAT database")));
        }
        $$ = true;
    }
    | /* EMPTY */                    { $$ = true; }
    ;

scalar_value:
    STRING_P                        { $$ = makeItemString(&$1); }
    | NULL_P                        { $$ = makeItemString(NULL); }
    | TRUE_P                        { $$ = makeItemBool(true); }
    | FALSE_P                        { $$ = makeItemBool(false); }
    | NUMERIC_P                        { $$ = makeItemNumeric(&$1); }
    | INT_P                            { $$ = makeItemNumeric(&$1); }
    | VARIABLE_P                    { $$ = makeItemVariable(&$1); }
    ;

starts_with_initial:
    STRING_P                        { $$ = makeItemString(&$1); }
    | VARIABLE_P                    { $$ = makeItemVariable(&$1); }
    ;

path_primary:
    scalar_value                    { $$ = $1; }
    | '$'                            { $$ = makeItemType(JPI_ROOT); }
    | '@'                            { $$ = makeItemType(JPI_CURRENT); }
    | LAST_P                        { $$ = makeItemType(JPI_LAST); }
    ;


comp_op:
    EQUAL_P                            { $$ = JPI_EQUAL; }
    | NOTEQUAL_P                    { $$ = JPI_NOT_EQUAL; }
    | LESS_P                        { $$ = JPI_LESS; }
    | GREATER_P                        { $$ = JPI_GREATER; }
    | LESSEQUAL_P                    { $$ = JPI_LESS_OR_EQUAL; }
    | GREATEREQUAL_P                { $$ = JPI_GREATER_OR_EQUAL; }
    ;

delimited_predicate:
    '(' predicate ')'                { $$ = $2; }
    | EXISTS_P '(' expr ')'            { $$ = makeItemUnary(JPI_EXISTS, $3); }
    ;

predicate:
    delimited_predicate                { $$ = $1; }
    | expr comp_op expr                { $$ = makeItemBinary($2, $1, $3); }
    | predicate AND_P predicate        { $$ = makeItemBinary(JPI_AND, $1, $3); }
    | predicate OR_P predicate        { $$ = makeItemBinary(JPI_OR, $1, $3); }
    | NOT_P delimited_predicate        { $$ = makeItemUnary(JPI_NOT, $2); }
    | '(' predicate ')' IS_P UNKNOWN_P { $$ = makeItemUnary(JPI_IS_UNKNOWN, $2); }
    | expr STARTS_P WITH_P starts_with_initial { $$ = makeItemBinary(JPI_STARTS_WITH, $1, $4); }
    | expr LIKE_REGEX_P STRING_P
    {
        JsonPathParseItem *jppitem;
        if (! makeItemLikeRegex($1, &$3, NULL, &jppitem)) {
            YYABORT;
        }
        $$ = jppitem;
    }
    | expr LIKE_REGEX_P STRING_P FLAG_P STRING_P
    {
        JsonPathParseItem *jppitem;
        if (DB_IS_CMPT(A_FORMAT)) {
            ereport(ERROR,
                    (errcode(ERRCODE_SYNTAX_ERROR),
                        errmsg("invalid input syntax for type %s", "jsonpath"),
                        errdetail("specifying like_regex flags is not supportted for A_FORMAT jsonpath")));
        }
        if (! makeItemLikeRegex($1, &$3, &$5, &jppitem)) {
            YYABORT;
        }
        $$ = jppitem;
    }
    ;

accessor_expr:
    path_primary                    { $$ = list_make1($1); }
    | '(' expr ')' accessor_op        { $$ = list_make2($2, $4); }
    | '(' predicate ')' accessor_op    { $$ = list_make2($2, $4); }
    | accessor_expr accessor_op        { $$ = lappend($1, $2); }
    ;

expr:
    accessor_expr                    { $$ = makeItemList($1); }
    | '(' expr ')'                    { $$ = $2; }
    | '-' expr %prec UMINUS            { $$ = makeItemUnary(JPI_MINUS, $2); }
    | '+' expr %prec UMINUS            { $$ = makeItemUnary(JPI_PLUS, $2); }
    | expr '+' expr                    { $$ = makeItemBinary(JPI_ADD, $1, $3); }
    | expr '-' expr                    { $$ = makeItemBinary(JPI_SUB, $1, $3); }
    | expr '*' expr                    { $$ = makeItemBinary(JPI_MUL, $1, $3); }
    | expr '/' expr                    { $$ = makeItemBinary(JPI_DIV, $1, $3); }
    | expr '%' expr                    { $$ = makeItemBinary(JPI_MOD, $1, $3); }
    ;

index_elem:
    expr                            { $$ = makeItemBinary(JPI_SUBSCRIPT, $1, NULL); }
    | expr TO_P expr                { $$ = makeItemBinary(JPI_SUBSCRIPT, $1, $3); }
    ;

index_list:
    index_elem
    {
        checkAFormatIndex($1);
        $$ = list_make1($1);
    }
    | index_list ',' index_elem
    {
        checkAFormatIndex($3);
        $$ = lappend($1, $3);
    }
    ;

array_accessor:
    '[' '*' ']'                        { $$ = makeItemType(JPI_ANY_ARRAY); }
    | '[' index_list ']'            { $$ = makeIndexArray($2); }
    ;

any_level:
    INT_P                            { $$ = pg_strtoint32($1.val); }
    | LAST_P                        { $$ = -1; }
    ;

any_path:
    ANY_P                            { $$ = makeAny(0, -1); }
    | ANY_P '{' any_level '}'        { $$ = makeAny($3, $3); }
    | ANY_P '{' any_level TO_P any_level '}'
                                    { $$ = makeAny($3, $5); }
    ;

accessor_op:
    '.' key                            { $$ = $2; }
    | '.' '*'                        { $$ = makeItemType(JPI_ANY_KEY); }
    | array_accessor                { $$ = $1; }
    | '.' any_path                    { $$ = $2; }
    | '.' method '(' ')'            { $$ = makeItemType($2); }
    | '?' '(' predicate ')'            { $$ = makeItemUnary(JPI_FILTER, $3); }
    | '.' DECIMAL_P '(' opt_csv_list ')'
        {
            if (list_length($4) == 0) {
                $$ = makeItemBinary(JPI_DECIMAL, NULL, NULL);
            } else if (list_length($4) == 1) {
                $$ = makeItemBinary(JPI_DECIMAL, (JsonPathParseItem*)linitial($4), NULL);
            } else if (list_length($4) == 2) {
                $$ = makeItemBinary(JPI_DECIMAL, (JsonPathParseItem*)linitial($4), (JsonPathParseItem*)lsecond($4));
            } else {
                ereport(ERROR,
                        (errcode(ERRCODE_SYNTAX_ERROR),
                         errmsg("invalid input syntax for type %s", "jsonpath"),
                         errdetail(".decimal() can only have an optional precision[,scale].")));
            }
        }
    | '.' DATETIME_P '(' opt_datetime_template ')'
        { $$ = makeItemUnary(JPI_DATETIME, $4); }
    | '.' TIME_P '(' opt_datetime_precision ')'
        { $$ = makeItemUnary(JPI_TIME, $4); }
    | '.' TIME_TZ_P '(' opt_datetime_precision ')'
        { $$ = makeItemUnary(JPI_TIME_TZ, $4); }
    | '.' TIMESTAMP_P '(' opt_datetime_precision ')'
        { $$ = makeItemUnary(JPI_TIMESTAMP, $4); }
    | '.' TIMESTAMP_TZ_P '(' opt_datetime_precision ')'
        { $$ = makeItemUnary(JPI_TIMESTAMP_TZ, $4); }
    ;

csv_elem:
    INT_P
        { $$ = makeItemNumeric(&$1); }
    | '+' INT_P %prec UMINUS
        { $$ = makeItemUnary(JPI_PLUS, makeItemNumeric(&$2)); }
    | '-' INT_P %prec UMINUS
        { $$ = makeItemUnary(JPI_MINUS, makeItemNumeric(&$2)); }
    ;

csv_list:
    csv_elem                        { $$ = list_make1($1); }
    | csv_list ',' csv_elem            { $$ = lappend($1, $3); }
    ;

opt_csv_list:
    csv_list                        { $$ = $1; }
    | /* EMPTY */                    { $$ = NULL; }
    ;

datetime_precision:
    INT_P                            { $$ = makeItemNumeric(&$1); }
    ;

opt_datetime_precision:
    datetime_precision                { $$ = $1; }
    | /* EMPTY */                    { $$ = NULL; }
    ;

datetime_template:
    STRING_P                        { $$ = makeItemString(&$1); }
    ;

opt_datetime_template:
    datetime_template                { $$ = $1; }
    | /* EMPTY */                    { $$ = NULL; }
    ;

key:
    key_name                        { $$ = makeItemKey(&$1); }
    ;

key_name:
    IDENT_P
    | STRING_P
    | TO_P
    | NULL_P
    | TRUE_P
    | FALSE_P
    | IS_P
    | UNKNOWN_P
    | EXISTS_P
    | STRICT_P
    | LAX_P
    | ABS_P
    | SIZE_P
    | TYPE_P
    | FLOOR_P
    | CEILING_P
    | KEYVALUE_P
    | LAST_P
    | STARTS_P
    | WITH_P
    | LIKE_REGEX_P
    | FLAG_P
    | STRINGFUNC_P
    | DECIMAL_P
    | NUMBER_P
    | DOUBLE_P
    | BOOLEAN_P
    | BIGINT_P
    | INTEGER_P
    | DATE_P
    | DATETIME_P
    | TIME_P
    | TIME_TZ_P
    | TIMESTAMP_P
    | TIMESTAMP_TZ_P
    ;

method:
    ABS_P                            { $$ = JPI_ABS; }
    | SIZE_P                        { $$ = JPI_SIZE; }
    | TYPE_P                        { $$ = JPI_TYPE; }
    | FLOOR_P                        { $$ = JPI_FLOOR; }
    | CEILING_P                        { $$ = JPI_CEILING; }
    | KEYVALUE_P                    { $$ = JPI_KEYVALUE; }
    | DATE_P                        { $$ = JPI_DATE; }
    | NUMBER_P                        { $$ = JPI_NUMBER; }
    | STRINGFUNC_P                    { $$ = JPI_STRING_FUNC; }
    | DOUBLE_P                        { $$ = JPI_DOUBLE; }
    | BOOLEAN_P                        { $$ = JPI_BOOLEAN; }
    | BIGINT_P                        { $$ = JPI_BIGINT; }
    | INTEGER_P                        { $$ = JPI_INTEGER; }
    ;
%%

static void jsonpath_yyerror(const char *msg)
{
    ereport(ERROR,
            (errcode(ERRCODE_SYNTAX_ERROR),
            errmsg("%s in json path expression", _(msg))));
}

/*
 * The helper functions below allocate and fill JsonPathParseItem's of various
 * types.
 */

static JsonPathParseItem * makeItemType(JsonPathItemType type)
{
    JsonPathParseItem *v = (JsonPathParseItem*)palloc(sizeof(*v));

    CHECK_FOR_INTERRUPTS();

    v->type = type;
    v->next = NULL;

    return v;
}

static JsonPathParseItem * makeItemString(JsonPathString *s)
{
    JsonPathParseItem *v;

    if (s == NULL) {
        v = makeItemType(JPI_NULL);
    } else {
        v = makeItemType(JPI_STRING);
        v->value.string.val = s->val;
        v->value.string.len = s->len;
    }

    return v;
}

static JsonPathParseItem * makeItemKey(JsonPathString *s)
{
    JsonPathParseItem *v;

    v = makeItemString(s);
    v->type = JPI_KEY;

    return v;
}

static JsonPathParseItem * makeItemNumeric(JsonPathString *s)
{
    JsonPathParseItem *v;

    v = makeItemType(JPI_NUMERIC);
    v->value.numeric =
        DatumGetNumeric(DirectFunctionCall3(numeric_in,
                                            CStringGetDatum(s->val),
                                            ObjectIdGetDatum(InvalidOid),
                                            Int32GetDatum(-1)));

    return v;
}

static JsonPathParseItem * makeItemBool(bool val)
{
    JsonPathParseItem *v = makeItemType(JPI_BOOL);

    v->value.boolean = val;

    return v;
}

static JsonPathParseItem * makeItemBinary
    (JsonPathItemType type, JsonPathParseItem *la, JsonPathParseItem *ra)
{
    JsonPathParseItem *v = makeItemType(type);

    v->value.args.left = la;
    v->value.args.right = ra;

    return v;
}

static void checkSingleAFormatIndex(JsonPathParseItem* item)
{
    if (((item->type == JPI_NUMERIC) || (item->type == JPI_VARIABLE) ||
        (item->type == JPI_LAST))) {
        return;
    }
    if ((item->type == JPI_ADD) || (item->type == JPI_SUB)) {
        JsonPathParseItem* la = item->value.args.left;
        JsonPathParseItem* ra = item->value.args.right;
        if (la->type == JPI_LAST &&
            (ra->type == JPI_NUMERIC || ra->type == JPI_VARIABLE)) {
            return;
        }
    }
    ereport(ERROR,
            (errcode(ERRCODE_SYNTAX_ERROR),
                errmsg("invalid input syntax for type %s", "jsonpath"),
                errdetail("A_FORMAT jsonpath array index can only be a non-negative integer, "
                "or an add/substraction expression of \"LAST\", with \"LAST\" "
                "as the left operand, and a non-negative integer as the right operand.")));
}

static void checkAFormatIndex(JsonPathParseItem* item)
{
    JsonPathParseItem* la = item->value.args.left;
    JsonPathParseItem* ra = item->value.args.right;

    if (!DB_IS_CMPT(A_FORMAT)) {
        return;
    }

    if (la != NULL) {
        checkSingleAFormatIndex(la);
    }
    if (ra != NULL) {
        checkSingleAFormatIndex(ra);
    }
}

static JsonPathParseItem * makeItemList(List *list)
{
    JsonPathParseItem *head,
               *end;
    ListCell   *cell;

    head = end = (JsonPathParseItem *) linitial(list);

    if (list_length(list) == 1) {
        return head;
    }

    /* append items to the end of already existing list */
    while (end->next) {
        end = end->next;
    }

    for_each_cell(cell, list_nth_cell(list, 1)) {
        JsonPathParseItem *c = (JsonPathParseItem *) lfirst(cell);

        end->next = c;
        end = c;
    }

    return head;
}

static JsonPathParseItem * makeIndexArray(List *list)
{
    JsonPathParseItem *v = makeItemType(JPI_INDEX_ARRAY);
    ListCell   *cell;
    int            i = 0;

    Assert(list != NIL);
    v->value.array.nelems = list_length(list);

    v->value.array.elems = (ArrayIndexRange*)palloc(sizeof(v->value.array.elems[0]) *
                                  v->value.array.nelems);

    foreach(cell, list) {
        JsonPathParseItem *jpi = (JsonPathParseItem*)lfirst(cell);

        Assert(jpi->type == JPI_SUBSCRIPT);

        v->value.array.elems[i].from = jpi->value.args.left;
        v->value.array.elems[i++].to = jpi->value.args.right;
    }

    return v;
}

static JsonPathParseItem * makeItemVariable(JsonPathString *s)
{
    JsonPathParseItem *v;

    v = makeItemType(JPI_VARIABLE);
    v->value.string.val = s->val;
    v->value.string.len = s->len;

    return v;
}

static JsonPathParseItem * makeAny(int first, int last)
{
    JsonPathParseItem *v = makeItemType(JPI_ANY);

    v->value.anybounds.first = (first >= 0) ? first : PG_UINT32_MAX;
    v->value.anybounds.last = (last >= 0) ? last : PG_UINT32_MAX;

    return v;
}

static JsonPathParseItem * makeItemUnary(
    JsonPathItemType type, JsonPathParseItem *a)
{
    JsonPathParseItem *v;

    if (type == JPI_PLUS && a->type == JPI_NUMERIC && !a->next) {
        return a;
    }

    if (type == JPI_MINUS && a->type == JPI_NUMERIC && !a->next) {
        v = makeItemType(JPI_NUMERIC);
        v->value.numeric =
            DatumGetNumeric(DirectFunctionCall1(numeric_uminus,
                                                NumericGetDatum(a->value.numeric)));
        return v;
    }

    v = makeItemType(type);

    v->value.arg = a;

    return v;
}

static bool makeItemLikeRegex(JsonPathParseItem *expr, JsonPathString *pattern,
    JsonPathString *flags, JsonPathParseItem **result)
{
    JsonPathParseItem *v = makeItemType(JPI_LIKE_REGEX);
    int            i;
    int            cflags;

    v->value.like_regex.expr = expr;
    v->value.like_regex.pattern = pattern->val;
    v->value.like_regex.patternlen = pattern->len;
    /* Parse the flags string, convert to bitmask.  Duplicate flags are OK. */
    v->value.like_regex.flags = 0;
    for (i = 0; flags && i < flags->len; i++) {
        switch (flags->val[i]) {
            case 'i':
                v->value.like_regex.flags |= JSP_REGEX_ICASE;
                break;
            case 's':
                v->value.like_regex.flags |= JSP_REGEX_DOTALL;
                break;
            case 'm':
                v->value.like_regex.flags |= JSP_REGEX_MLINE;
                break;
            case 'x':
                v->value.like_regex.flags |= JSP_REGEX_WSPACE;
                break;
            case 'q':
                v->value.like_regex.flags |= JSP_REGEX_QUOTE;
                break;
            default:
                ereport(ERROR,
                        (errcode(ERRCODE_SYNTAX_ERROR),
                         errmsg("invalid input syntax for type %s", "jsonpath"),
                         errdetail("Unrecognized flag character \"%.*s\" in LIKE_REGEX predicate.",
                                   pg_mblen(flags->val + i), flags->val + i)));
                break;
        }
    }

    /* Convert flags to what pg_regcomp needs */
    if (!JspConvertRegexFlags(v->value.like_regex.flags, &cflags)) {
        return false;
    }

    /* check regex validity */
    {
        regex_t        re_tmp;
        pg_wchar   *wpattern;
        int            wpattern_len;
        int            re_result;

        wpattern = (pg_wchar *) palloc((pattern->len + 1) * sizeof(pg_wchar));
        wpattern_len = pg_mb2wchar_with_len(pattern->val,
                                            wpattern,
                                            pattern->len);
        if ((re_result = pg_regcomp(&re_tmp, wpattern, wpattern_len, cflags,
                                    DEFAULT_COLLATION_OID)) != REG_OKAY) {
            char        errMsg[100];

            pg_regerror(re_result, &re_tmp, errMsg, sizeof(errMsg));
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_REGULAR_EXPRESSION),
                     errmsg("invalid regular expression: %s", errMsg)));
        }

        pg_regfree(&re_tmp);
    }

    *result = v;

    return true;
}

/*
 * Convert from XQuery regex flags to those recognized by our regex library.
 */
bool JspConvertRegexFlags(uint32 xflags, int *result)
{
    /* By default, XQuery is very nearly the same as Spencer's AREs */
    int            cflags = REG_ADVANCED;

    /* Ignore-case means the same thing, too, modulo locale issues */
    if (xflags & JSP_REGEX_ICASE) {
        cflags |= REG_ICASE;
    }

    /* Per XQuery spec, if 'q' is specified then 'm', 's', 'x' are ignored */
    if (xflags & JSP_REGEX_QUOTE) {
        cflags &= ~REG_ADVANCED;
        cflags |= REG_QUOTE;
    } else {
        /* Note that dotall mode is the default in POSIX */
        if (!(xflags & JSP_REGEX_DOTALL)) {
            cflags |= REG_NLSTOP;
        }
        if (xflags & JSP_REGEX_MLINE) {
            cflags |= REG_NLANCH;
        }

        /*
         * XQuery's 'x' mode is related to Spencer's expanded mode, but it's
         * not really enough alike to justify treating JSP_REGEX_WSPACE as
         * REG_EXPANDED.  For now we treat 'x' as unimplemented; perhaps in
         * future we'll modify the regex library to have an option for
         * XQuery-style ignore-whitespace mode.
         */
        if (xflags & JSP_REGEX_WSPACE) {
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("XQuery \"x\" flag (expanded regular expressions) is not implemented")));
        }
    }

    *result = cflags;

    return true;
}

#undef yyerror
#undef yylval
#undef yylloc
#undef yylex

#include "jsonpath_scan.inc"
