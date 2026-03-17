%option prefix="pgtsql_core_yy"

%x      xbr

xbrstart        \[
xbrstop         \]
xbrinside       [^\]]+

hex_cont [0-9A-Za-z]

%s		tsql
tsql_hex		0[xX]{hex_cont}*
tsql_ident	@{ident_cont}*
tsql_name    [A-Za-z\200-\377_0-9\$\#\@]
tsql_ttname  \#?\#{tsql_name}*
