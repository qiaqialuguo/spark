--SET spark.sql.binaryOutputStyle=UTF8;

SELECT X'';
SELECT X'4561736F6E2059616F20323031382D31312D31373A31333A33333A3333';
SELECT CAST('Spark' as BINARY);
SELECT array( X'', X'4561736F6E2059616F20323031382D31312D31373A31333A33333A3333', CAST('Spark' as BINARY));
