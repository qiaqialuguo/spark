-- Prepare some test data.
--------------------------
drop table if exists t;
create table t(x int, y string) using csv;
insert into t values (0, 'abc'), (1, 'def');

drop table if exists other;
create table other(a int, b int) using json;
insert into other values (1, 1), (1, 2), (2, 4);

drop table if exists st;
create table st(x int, col struct<i1:int, i2:int>) using parquet;
insert into st values (1, (2, 3));

create temporary view courseSales as select * from values
  ("dotNET", 2012, 10000),
  ("Java", 2012, 20000),
  ("dotNET", 2012, 5000),
  ("dotNET", 2013, 48000),
  ("Java", 2013, 30000)
  as courseSales(course, year, earnings);

create temporary view courseEarnings as select * from values
  ("dotNET", 15000, 48000, 22500),
  ("Java", 20000, 30000, NULL)
  as courseEarnings(course, `2012`, `2013`, `2014`);

create temporary view courseEarningsAndSales as select * from values
  ("dotNET", 15000, NULL, 48000, 1, 22500, 1),
  ("Java", 20000, 1, 30000, 2, NULL, NULL)
  as courseEarningsAndSales(
    course, earnings2012, sales2012, earnings2013, sales2013, earnings2014, sales2014);

create temporary view yearsWithComplexTypes as select * from values
  (2012, array(1, 1), map('1', 1), struct(1, 'a')),
  (2013, array(2, 2), map('2', 2), struct(2, 'b'))
  as yearsWithComplexTypes(y, a, m, s);

-- SELECT operators: positive tests.
---------------------------------------

-- Selecting a constant.
table t
|> select 1 as x;

-- Selecting attributes.
table t
|> select x, y;

-- Chained pipe SELECT operators.
table t
|> select x, y
|> select x + length(y) as z;

-- Using the VALUES list as the source relation.
values (0), (1) tab(col)
|> select col * 2 as result;

-- Using a table subquery as the source relation.
(select * from t union all select * from t)
|> select x + length(y) as result;

-- Enclosing the result of a pipe SELECT operation in a table subquery.
(table t
 |> select x, y
 |> select x)
union all
select x from t where x < 1;

-- Selecting struct fields.
(select col from st)
|> select col.i1;

table st
|> select st.col.i1;

-- Expression subqueries in the pipe operator SELECT list.
table t
|> select (select a from other where x = a limit 1) as result;

-- Pipe operator SELECT inside expression subqueries.
select (values (0) tab(col) |> select col) as result;

-- Aggregations are allowed within expression subqueries in the pipe operator SELECT list as long as
-- no aggregate functions exist in the top-level select list.
table t
|> select (select any_value(a) from other where x = a limit 1) as result;

-- Lateral column aliases in the pipe operator SELECT list.
table t
|> select x + length(x) as z, z + 1 as plus_one;

-- Window functions are allowed in the pipe operator SELECT list.
table t
|> select first_value(x) over (partition by y) as result;

select 1 x, 2 y, 3 z
|> select 1 + sum(x) over (),
     avg(y) over (),
     x,
     avg(x+1) over (partition by y order by z) AS a2
|> select a2;

table t
|> select x, count(*) over ()
|> select x;

-- DISTINCT is supported.
table t
|> select distinct x, y;

-- SELECT * is supported.
table t
|> select *;

table t
|> select * except (y);

-- Hints are supported.
table t
|> select /*+ repartition(3) */ *;

table t
|> select /*+ repartition(3) */ distinct x;

table t
|> select /*+ repartition(3) */ all x;

-- SELECT operators: negative tests.
---------------------------------------

-- Aggregate functions are not allowed in the pipe operator SELECT list.
table t
|> select sum(x) as result;

table t
|> select y, length(y) + sum(x) as result;

-- WHERE operators: positive tests.
-----------------------------------

-- Filtering with a constant predicate.
table t
|> where true;

-- Filtering with a predicate based on attributes from the input relation.
table t
|> where x + length(y) < 4;

-- Two consecutive filters are allowed.
table t
|> where x + length(y) < 4
|> where x + length(y) < 3;

-- It is possible to use the WHERE operator instead of the HAVING clause when processing the result
-- of aggregations. For example, this WHERE operator is equivalent to the normal SQL "HAVING x = 1".
(select x, sum(length(y)) as sum_len from t group by x)
|> where x = 1;

-- Filtering by referring to the table or table subquery alias.
table t
|> where t.x = 1;

table t
|> where spark_catalog.default.t.x = 1;

-- Filtering using struct fields.
(select col from st)
|> where col.i1 = 1;

table st
|> where st.col.i1 = 2;

-- Expression subqueries in the WHERE clause.
table t
|> where exists (select a from other where x = a limit 1);

-- Aggregations are allowed within expression subqueries in the pipe operator WHERE clause as long
-- no aggregate functions exist in the top-level expression predicate.
table t
|> where (select any_value(a) from other where x = a limit 1) = 1;

-- WHERE operators: negative tests.
-----------------------------------

-- Aggregate functions are not allowed in the top-level WHERE predicate.
-- (Note: to implement this behavior, perform the aggregation first separately and then add a
-- pipe-operator WHERE clause referring to the result of aggregate expression(s) therein).
table t
|> where sum(x) = 1;

table t
|> where y = 'abc' or length(y) + sum(x) = 1;

-- Window functions are not allowed in the WHERE clause (pipe operators or otherwise).
table t
|> where first_value(x) over (partition by y) = 1;

select * from t where first_value(x) over (partition by y) = 1;

-- Pipe operators may only refer to attributes produced as output from the directly-preceding
-- pipe operator, not from earlier ones.
table t
|> select x, length(y) as z
|> where x + length(y) < 4;

-- If the WHERE clause wants to filter rows produced by an aggregation, it is not valid to try to
-- refer to the aggregate functions directly; it is necessary to use aliases instead.
(select x, sum(length(y)) as sum_len from t group by x)
|> where sum(length(y)) = 3;

-- Pivot and unpivot operators: positive tests.
-----------------------------------------------

table courseSales
|> select `year`, course, earnings
|> pivot (
     sum(earnings)
     for course in ('dotNET', 'Java')
  );

table courseSales
|> select `year` as y, course as c, earnings as e
|> pivot (
     sum(e) as s, avg(e) as a
     for y in (2012 as firstYear, 2013 as secondYear)
   );

-- Pivot on multiple pivot columns with aggregate columns of complex data types.
select course, `year`, y, a
from courseSales
join yearsWithComplexTypes on `year` = y
|> pivot (
     max(a)
     for (y, course) in ((2012, 'dotNET'), (2013, 'Java'))
   );

-- Pivot on pivot column of struct type.
select earnings, `year`, s
from courseSales
join yearsWithComplexTypes on `year` = y
|> pivot (
     sum(earnings)
     for s in ((1, 'a'), (2, 'b'))
   );

table courseEarnings
|> unpivot (
     earningsYear for `year` in (`2012`, `2013`, `2014`)
   );

table courseEarnings
|> unpivot include nulls (
     earningsYear for `year` in (`2012`, `2013`, `2014`)
   );

table courseEarningsAndSales
|> unpivot include nulls (
     (earnings, sales) for `year` in (
       (earnings2012, sales2012) as `2012`,
       (earnings2013, sales2013) as `2013`,
       (earnings2014, sales2014) as `2014`)
   );

-- Pivot and unpivot operators: negative tests.
-----------------------------------------------

-- The PIVOT operator refers to a column 'year' is not available in the input relation.
table courseSales
|> select course, earnings
|> pivot (
     sum(earnings)
     for `year` in (2012, 2013)
   );

-- Non-literal PIVOT values are not supported.
table courseSales
|> pivot (
     sum(earnings)
     for `year` in (course, 2013)
   );

-- The PIVOT and UNPIVOT clauses are mutually exclusive.
table courseSales
|> select course, earnings
|> pivot (
     sum(earnings)
     for `year` in (2012, 2013)
   )
   unpivot (
     earningsYear for `year` in (`2012`, `2013`, `2014`)
   );

table courseSales
|> select course, earnings
|> unpivot (
     earningsYear for `year` in (`2012`, `2013`, `2014`)
   )
   pivot (
     sum(earnings)
     for `year` in (2012, 2013)
   );

-- Multiple PIVOT and/or UNPIVOT clauses are not supported in the same pipe operator.
table courseSales
|> select course, earnings
|> pivot (
     sum(earnings)
     for `year` in (2012, 2013)
   )
   pivot (
     sum(earnings)
     for `year` in (2012, 2013)
   );

table courseSales
|> select course, earnings
|> unpivot (
     earningsYear for `year` in (`2012`, `2013`, `2014`)
   )
   unpivot (
     earningsYear for `year` in (`2012`, `2013`, `2014`)
   )
   pivot (
     sum(earnings)
     for `year` in (2012, 2013)
   );

-- Sampling operators: positive tests.
--------------------------------------

-- We will use the REPEATABLE clause and/or adjust the sampling options to either remove no rows or
-- all rows to help keep the tests deterministic.
table t
|> tablesample (100 percent) repeatable (0);

table t
|> tablesample (2 rows) repeatable (0);

table t
|> tablesample (bucket 1 out of 1) repeatable (0);

table t
|> tablesample (100 percent) repeatable (0)
|> tablesample (5 rows) repeatable (0)
|> tablesample (bucket 1 out of 1) repeatable (0);

-- Sampling operators: negative tests.
--------------------------------------

-- The sampling method is required.
table t
|> tablesample ();

-- Negative sampling options are not supported.
table t
|> tablesample (-100 percent);

table t
|> tablesample (-5 rows);

-- The sampling method may not refer to attribute names from the input relation.
table t
|> tablesample (x rows);

-- The bucket number is invalid.
table t
|> tablesample (bucket 2 out of 1);

-- Byte literals are not supported.
table t
|> tablesample (200b) repeatable (0);

-- Invalid byte literal syntax.
table t
|> tablesample (200) repeatable (0);

-- Cleanup.
-----------
drop table t;
drop table other;
drop table st;
