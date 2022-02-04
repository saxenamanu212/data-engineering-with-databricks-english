-- Databricks notebook source
-- MAGIC %md-sandbox
-- MAGIC 
-- MAGIC <div style="text-align: center; line-height: 0; padding-top: 9px;">
-- MAGIC   <img src="https://databricks.com/wp-content/uploads/2018/03/db-academy-rgb-1200px.png" alt="Databricks Learning" style="width: 600px">
-- MAGIC </div>

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC # Cleaning Data
-- MAGIC 
-- MAGIC Most transformations completed with Spark SQL will be familiar to SQL-savvy developers.
-- MAGIC 
-- MAGIC As we inspect and clean our data, we'll need to construct various column expressions and queries to express transformations to apply on our dataset.  
-- MAGIC 
-- MAGIC Column expressions are constructed from existing columns, operators, and built-in Spark SQL functions. They can be used in `SELECT` statements to express transformations that create new columns from datasets. 
-- MAGIC 
-- MAGIC Along with `SELECT`, many additional query commands can be used to express transformations in Spark SQL, including `WHERE`, `DISTINCT`, `ORDER BY`, `GROUP BY`, etc.
-- MAGIC 
-- MAGIC In this notebook, we'll review a few concepts that might differ from other systems you're used to, as well as calling out a few useful functions for common operations.
-- MAGIC 
-- MAGIC We'll pay special attention to behaviors around `NULL` values, as well as formatting strings and datetime fields.
-- MAGIC 
-- MAGIC ## Learning Objectives
-- MAGIC By the end of this notebook, students should feel comfortable:
-- MAGIC - Summarizing datasets and describe null behaviors
-- MAGIC - Retrieving and removing duplicates
-- MAGIC - Validating datasets for expected counts, missing values, and duplicate records
-- MAGIC - Applying common transformations to clean and transform data

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Run Setup
-- MAGIC 
-- MAGIC The setup script will create the data and declare necessary values for the rest of this notebook to execute.

-- COMMAND ----------

-- MAGIC %run ../Includes/setup-cleaning

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We'll work with new users records in `users_dirty` table for this lesson.

-- COMMAND ----------

SELECT * FROM users_dirty

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC ## Inspect Data
-- MAGIC 
-- MAGIC Let's start by counting values in each field of our data.

-- COMMAND ----------

SELECT count(user_id), count(user_first_touch_timestamp), count(email), count(updated), count(*)
FROM users_dirty

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC Note that `count(col)` skips `NULL` values when counting specific columns or expressions.
-- MAGIC 
-- MAGIC However, `count(*)` is a special case that counts the total number of rows (including rows that are only `NULL` values).
-- MAGIC 
-- MAGIC To count null values, use the `count_if` function or `WHERE` clause to provide a condition that filters for records where the value `IS NULL`.

-- COMMAND ----------

SELECT
  count_if(user_id IS NULL) missing_user_ids, 
  count_if(user_first_touch_timestamp IS NULL) missing_timestamps, 
  count_if(email IS NULL) missing_emails,
  count_if(updated IS NULL) missing_updates
FROM users_dirty

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Clearly there are at least a handful of null values in all of our fields. Let's try to discover what is causing this.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Distinct Records
-- MAGIC 
-- MAGIC Start by looking for distinct rows.

-- COMMAND ----------

SELECT count(DISTINCT(*))
FROM users_dirty

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Note that when we called `DISTINCT(*)`, by default we ignored all rows containing **any** null values; as such, our result is the same as the count of user emails above.
-- MAGIC 
-- MAGIC Let's look at the `user_id` column.

-- COMMAND ----------

SELECT count(DISTINCT(user_id))
FROM users_dirty

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Because `user_id` is generated alongside the `user_first_touch_timestamp`, these fields should always be in parity for counts.

-- COMMAND ----------

SELECT count(DISTINCT(user_first_touch_timestamp))
FROM users_dirty

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Here we note that while there are some duplicate records relative to our total row count, we have a much higher number of distinct values.
-- MAGIC 
-- MAGIC Let's go ahead and combine our distinct counts with columnar counts to see these values side-by-side.

-- COMMAND ----------

SELECT 
  count(user_id) total_ids, count(DISTINCT user_id) unique_ids,
  count(email) total_emails, count(DISTINCT email) unique_emails,
  count(updated) total_updates, count(DISTINCT(updated)) unique_updates,
  count(*) total_rows, count(DISTINCT(*)) unique_non_null_rows
FROM users_dirty

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Based on the above summary, we know:
-- MAGIC * All of our emails are unique
-- MAGIC * Our emails contain the largest number of null values
-- MAGIC * The `updated` column contains only 1 distinct value, but most are non-null

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC ## Deduplicate Rows
-- MAGIC Based on the above behavior, what do you expect will happen if we use `DISTINCT *` to try to remove duplicate records?

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW users_deduped AS
  SELECT DISTINCT(*) FROM users_dirty;

SELECT * FROM users_deduped

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Note in the preview above that there appear to be null values, even though our `COUNT(DISTINCT(*))` ignored these nulls.
-- MAGIC 
-- MAGIC How many rows do you expect passed through this `DISTINCT` command?

-- COMMAND ----------

SELECT COUNT(*) FROM users_deduped

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Note that we now have a completely new number.
-- MAGIC 
-- MAGIC Spark skips null values while counting values in a column or counting distinct values for a field, but does not omit rows with nulls from a `DISTINCT` query.
-- MAGIC 
-- MAGIC Indeed, the reason we're seeing a new number that is 1 higher than previous counts is because we have 3 rows that are all nulls (here included as a single distinct row).

-- COMMAND ----------

SELECT * FROM users_dirty
WHERE
  user_id IS NULL AND
  user_first_touch_timestamp IS NULL AND
  email IS NULL AND
  updated IS NULL

-- COMMAND ----------

-- MAGIC %md  
-- MAGIC ## Deduplicate Based on Specific Columns
-- MAGIC 
-- MAGIC Recall that `user_id` and `user_first_touch_timestamp` should form unique tuples, as they are both generated when a given user is first encountered.
-- MAGIC 
-- MAGIC We can see that we have some null values in each of these fields; exclude nulls counting the distinct number of pairs for these fields will get us the correct count for distinct values in our table.

-- COMMAND ----------

SELECT COUNT(DISTINCT(user_id, user_first_touch_timestamp))
FROM users_dirty
WHERE user_id IS NOT NULL

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Here, we'll use these distinct pairs to remove unwanted rows from our data.
-- MAGIC 
-- MAGIC The code below uses `GROUP BY` to remove duplicate records based on `user_id` and `user_first_touch_timestamp`.
-- MAGIC 
-- MAGIC The `max()` aggregate function is used on the `email` column as a hack to capture non-null emails when multiple records are present; in this batch, all `updated` values were equivalent, but we need to use an aggregate function to keep this value in the result of our group by.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW deduped_users AS
SELECT user_id, user_first_touch_timestamp, max(email) email, max(updated) updated
FROM users_dirty
WHERE user_id IS NOT NULL
GROUP BY user_id, user_first_touch_timestamp;

SELECT count(*) FROM deduped_users

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC ## Validate Datasets
-- MAGIC We've visually confirmed that our counts are as expected, based our manual review.
-- MAGIC  
-- MAGIC Below, we programmatically do some validation using simple filters and `WHERE` clauses.
-- MAGIC 
-- MAGIC Validate that the `user_id` for each row is unique.

-- COMMAND ----------

SELECT max(row_count) <= 1 no_duplicate_ids FROM (
  SELECT user_id, count(*) row_count
  FROM deduped_users
  GROUP BY user_id)

-- COMMAND ----------

-- MAGIC %md Confirm that each email is associated with at most one `user_id`.

-- COMMAND ----------

SELECT max(user_id_count) <= 1 at_most_one_id FROM (
  SELECT email, count(user_id) user_id_count
  FROM deduped_users
  WHERE email IS NOT NULL
  GROUP BY email)

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC ## Date Format and Regex
-- MAGIC Now that we've removed null fields and eliminated duplicates, we may wish to extract further value out of the data.
-- MAGIC 
-- MAGIC The code below:
-- MAGIC - Correctly scales and casts the `user_first_touch_timestamp` to a valid timestamp
-- MAGIC - Extracts the calendar data and clock time for this timestamp in human readable format
-- MAGIC - Uses `regexp_extract` to extract the domains from the email column using regex

-- COMMAND ----------

SELECT *,
  date_format(first_touch, "MMM d, yyyy") first_touch_date,
  date_format(first_touch, "HH:mm:ss") first_touch_time,
  regexp_extract(email, "(?<=@).+", 0) email_domain
FROM (
  SELECT *,
    CAST(user_first_touch_timestamp / 1e6 AS timestamp) first_touch 
  FROM deduped_users
)

-- COMMAND ----------

-- MAGIC %md-sandbox
-- MAGIC &copy; 2022 Databricks, Inc. All rights reserved.<br/>
-- MAGIC Apache, Apache Spark, Spark and the Spark logo are trademarks of the <a href="https://www.apache.org/">Apache Software Foundation</a>.<br/>
-- MAGIC <br/>
-- MAGIC <a href="https://databricks.com/privacy-policy">Privacy Policy</a> | <a href="https://databricks.com/terms-of-use">Terms of Use</a> | <a href="https://help.databricks.com/">Support</a>