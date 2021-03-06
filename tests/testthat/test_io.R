library(civis)
context("io")

# read_civis ------------------------------------------------------------------

test_that("read_civis reads < 2gb files from memory", {
  mock_df_string <- "a,b\n1,sentimental\n2,centipede"
  con <- textConnection(mock_df_string)
  mock_df <- read.csv(con)
  close(con)
  rm(con)
  mock_sql_job <- function(...) list(script_id = 1337, run_id = 007)
  mock_GET_result <- function(...) {

    GET_result <- list("url" = "http://www.fakeurl.com",
                       "headers" = list("Content-Type" = "text/csv"),
                       "content" = charToRaw(mock_df_string))
    class(GET_result) <- "response"
    return(GET_result)
  }
  mock_get_sql_runs <- function(...) {
    list(state = "succeeded",
         output = list(list(fileId = 1234))
    )
  }
  with_mock(
    `civis::start_scripted_sql_job` = mock_sql_job,
    `civis::scripts_post_sql_runs` = function(...) list(id = 1001),
    `civis::scripts_get_sql_runs` = mock_get_sql_runs,
    `civis::files_get` = function(...) list(fileSize = 10),
    `civis::download_script_results` = mock_GET_result,
    `civis::stop_for_status` = function(...) return(TRUE),
    expect_equal(mock_df, read_civis(x = "lazy", database = "jellyfish")),
    expect_equal(mock_df, read_civis(dbplyr::sql("SELECT * FROM lazy"),
                                     database = "jellyfish"))
  )
})

test_that("read_civis.sql reads > 2gb files from file", {
  mock_df <- data.frame(a = 1:2, b = c("sentimental", "centipede"))
  mock_get_sql_runs <- function(...) {
    list(state = "succeeded",
         output = list(list(fileId = 1234))
    )
  }
  mock_sql_job <- function(...) list(script_id = 1337, run_id = 007)
  mock_download_script_results <- function(id, run_id, filename) {
    write.csv(mock_df, file = filename, row.names = FALSE)
    return(filename)
  }
  with_mock(
    `civis::start_scripted_sql_job` = mock_sql_job,
    `civis::scripts_post_sql_runs` = function(...) list(id = 1001),
    `civis::scripts_get_sql_runs` = mock_get_sql_runs,
    `civis::files_get` = function(...) list(fileSize = 4E9),
    `civis::download_script_results` = mock_download_script_results,
    `civis::stop_for_status` = function(...) return(TRUE),
    expect_equal(mock_df, read_civis(x = "lazy", database = "jellyfish")),
    expect_equal(mock_df, read_civis(dbplyr::sql("SELECT * FROM lazy"),
                                     database = "jellyfish"))
  )
})

test_that("read_civis.sql produces catchable error when query returns no rows", {
  no_results_resp <- list(state = "succeeded", output = list())

  mock_sql_job <- function(...) list(script_id = 561, run_id = 43)
  with_mock(
    `civis::start_scripted_sql_job` = mock_sql_job,
    `civis::scripts_get_sql_runs` = function(...) no_results_resp,
    try_err <- try(read_civis(dbplyr::sql("SELECT 0"), database = "arrgh"), silent = TRUE),
    expect_true("empty_result_error" %in% class(attr(try_err, "condition")))
  )
})

test_that("read_civis.numeric reads a csv", {
  d <- data.frame(a = 1:2, b = c("sentimental", "centipede"))
  mock_response <- function(...) {
    structure(list(url = "http://www.fakeurl.com", status_code = 200),
              class = "response")
  }
  with_mock(
    `civis::files_get` =  function(...) list(fileUrl = "fakeurl.com"),
    `httr::GET` = mock_response,
    `civis::download_civis` = function(id, fn) write.csv(d, file = fn),
    expect_equal(d, read_civis(123, using = read.csv, row.names = 1))
  )
})

test_that("read_civis.numeric fails for NA", {
  msg <- "File ID cannot be NA."
  expect_error(read_civis(as.numeric(NA)), msg)
})

# write_civis -----------------------------------------------------------------

test_that("write_civis.character returns meta data if successful", {
  mock_df <- cbind.data.frame(a = c(1,2), b = c("cape-cod", "clams"))
  write("", file = "mockfile")
  res <- with_mock(
    `civis::start_import_job` = function(...) {
      list(uploadUri = "fake", id = 1)
    },
    `civis::tables_post_refresh` = function(id) "",
    `httr::PUT` = function(...) list(status_code = 200),
    `civis::imports_post_files_runs` = function(...) list(""),
    `civis::imports_get_files_runs` = function(...) list(state = "succeeded"),
      write_civis("mockfile", "mock.table", "mockdb")
    )
  unlink("mockfile")
  expect_equal(get_status(res), "succeeded")
})

test_that("write_civis.character fails if file doesn't exist", {
  mock_df <- cbind.data.frame(a = c(1,2), b = c("cape-cod", "clams"))
  err_msg <- with_mock(
    `civis::start_import_job` = function(...) {
      list(uploadUri = "fake")
    },
    `httr::PUT` = function(...) list(status_code = 200),
    `civis::imports_post_files_runs` = function(...) list(""),
    `civis::imports_get_files_runs` = function(...) list(state = "succeeded"),
    tryCatch(write_civis("mockfile", "mock.table", "mockdb"), error = function(e) e$message)
  )
  msg <- "file.exists(x) is not TRUE"
  expect_equal(err_msg, msg)
})

test_that("write_civis.data.frame returns meta data if successful", {
  mock_df <- cbind.data.frame(a = c(1,2), b = c("cape-cod", "clams"))
  res <- with_mock(
    `civis::start_import_job` = function(...) {
      list(uploadUri = "fake", id = 1)
    },
    `civis::tables_post_refresh` = function(id) "",
    `httr::PUT` = function(...) list(status_code = 200),
    `civis::imports_post_files_runs` = function(...) list(""),
    `civis::imports_get_files_runs` = function(...) list(state = "succeeded"),
    `civis::tables_list` = function(...) 1,
    write_civis(mock_df, "mock.table", "mockdb")
  )
  expect_equal(get_status(res), "succeeded")
})

test_that("write_civis.character warns under failure", {
  mock_df <- cbind.data.frame(a = c(1,2), b = c("cape-cod", "clams"))
  with_mock(
    `civis::start_import_job` = function(...) {
      list(uploadUri = "fake", id = -999)
    },
    `httr::PUT` = function(...) list(status_code = 200),
    `civis::imports_post_files_runs` = function(...) "",
    `civis::imports_get_files_runs` = function(...) list(state = "failed"),
    `httr::content` = function(...) "error",
    expect_error(
      write_civis("mockfile", "mock.table", "mockdb"))
  )
})

test_that("write_civis.numeric calls imports_post_syncs correctly", {
  ips <- mock(imports_post_syncs)
  with_mock(
    `civis:::get_database_id` = function(...) 32,
    `civis:::default_credential` = function(...) 999,
    `civis::imports_post` = function(...) list(id = 2),
    `civis::imports_post_syncs` = ips,
    `civis::jobs_post_runs` = function(...) list(id = 4),
    `civis::jobs_get_runs` = function(...) list(state = "succeeded"),
    res <- write_civis(1234, "mock.table", "mockdb"),
    expect_equal(get_status(res), "succeeded"),
    expect_args(ips, 1, 2,
                list(file = list(id = 1234)),
                destination = list(database_table =
                                     list(schema = "mock", table = "table")),
                advanced_options = list(max_errors = NULL,
                     existing_table_rows = "fail",
                     distkey = NULL,
                     diststyle = NULL,
                     sortkey1 = NULL,
                     sortkey2 = NULL,
                     column_delimiter = "comma"))
  )
})

test_that("write_civis fails if no db given and default not provided", {
  with_mock(
    `civis::get_default_database` = function(...) NULL,
    err_msg <- tryCatch(write_civis(iris), error = function(e) e$message),
    db_err <- tryCatch(get_db(NULL), error = function(e) e$message),
    expect_equal(err_msg, db_err)
  )
})

test_that("write_civis.numeric fails for NA", {
  msg <- "File ID cannot be NA."
  expect_error(write_civis(as.numeric(NA)), msg)
})

test_that("write_civis_file fails if file doesn't exist", {
  msg <- "file.exists(x) is not TRUE"
  err_msg <- tryCatch(write_civis_file("asdf"), error = function(e) e$message)
  expect_equal(msg, err_msg)
})

test_that("write_civis_file.character returns a file id", {
  write("", "mockfile.txt")
  with_mock(
    `civis::files_post` = function(...) list(uploadFields = list("fakeurl.com"), id = 5),
    `httr::upload_file` = function(...) "the file",
    `httr::POST` = function(...) structure(list(status_code = 200), class = "response"),
     expect_equal(write_civis_file("mockfile.txt", name = "mockfile.txt"), 5)
  )
  unlink("mockfile.txt")
})

test_that("write_civis_file.default returns a file id", {
  mock_df <- data.frame(a = c(1,2), b = c("cape-cod", "clams"))
  with_mock(
    `civis::files_post` = function(...) list(uploadFields = list("fakeurl.com"), id = 5),
    `httr::upload_file` = function(...) "the file",
    `httr::POST` = function(...) structure(list(status_code = 200), class = "response"),
    expect_equal(write_civis_file(mock_df), 5),
    expect_equal(write_civis_file(as.list(mock_df)), 5),
    expect_equal(write_civis_file(1:3), 5)
  )
})

test_that("write_civis_file calls multipart_unload for big files", {
  fake_file_size <- mock(file.size)
  mockery::stub(write_civis_file.character, "file.size", MIN_MULTIPART_SIZE + 1)
  fn <- tempfile()
  file.create(fn)
  with_mock(
    `civis::multipart_upload` = function(...) 1,
    expect_equal(write_civis_file(fn, name = "asdf"), 1)
  )
  unlink(fn)
})

# download_civis --------------------------------------------------------------

test_that("download_civis raises an error if destination file is not specified", {
  expect_error(download_civis("mock.table", "mockdb"),
               "argument \"file\" is missing")
})

test_that("download_civis raises an error if destination file already exists", {
  local_file <- "my_table.csv"
  file.create(local_file)
  expect_error(download_civis("mock.table", "mockdb", local_file, overwrite = FALSE),
               "File already exists")
  file.remove(local_file) # Clean up after testing
})

test_that("download_civis.numeric fails for NA", {
  msg <- "File ID cannot be NA."
  expect_error(write_civis(as.numeric(NA)), msg)
})


# query_civis -----------------------------------------------------------------

test_that("query_civis returns object from await", {
  with_mock(
    `civis::get_database_id` = function(...) TRUE,
    `civis::default_credential` = function(...) TRUE,
    `civis::queries_post` = function(...) list(id = "query_id"),
    `civis::queries_get` = function(...) list(state = 'succeeded'),
    expect_equal(get_status(query_civis("query", "database")), 'succeeded')
  )
})

test_that("query_civis.numeric fails for NA", {
  msg <- "Query ID cannot be NA."
  expect_error(query_civis(as.numeric(NA)), msg)
})

test_that("query_civis_file.sql works", {
  with_mock(
    `civis::get_database_id` = function(...) TRUE,
    `civis::get_db` = function(...) "asdf",
    `civis::default_credential` = function(...) TRUE,
    `civis:::start_scripted_sql_job` = function(...) list(script_id = 1, run_id = 1),
    `civis::scripts_get_sql_runs` = function(...) list(state = "succeeded",
                                                       output = list(list(fileId = 1))),
    expect_equal(query_civis_file(sql("asdf")), 1)
  )
})

test_that("query_civis_file.character errors if not schema.tablename", {
  msg <- 'Argument x should be "schema.tablename". Did you mean x = sql("...")?'
  expect_error(query_civis_file("select asdf"), msg)
})

test_that("query_civis_file.numeric works", {
  with_mock(
    `civis::scripts_post_sql_runs` = function(...) list(id = 333),
    `civis::scripts_get_sql_runs` = function(...) list(state = "succeeded",
                                                       output = list(list(fileId = 1))),
    expect_equal(query_civis_file(234), 1)
  )
})

test_that("query_civis_file.numeric fails for NA", {
  msg <- "Query ID cannot be NA"
  expect_error(query_civis(as.numeric(NA), msg))
})

test_that("transfer_table succeeds", {
  res <- with_mock(
    `civis::default_credential` = function(...) 1,
    `civis::get_database_id` = function(...) 32,
    `civis::imports_post` = function(...) list(id = 999),
    `civis::imports_post_syncs` = function(...) NULL,
    `civis::imports_post_runs` = function(...) list(runId = 999),
    `civis::imports_get_files_runs` = function(...) list(state = "succeeded"),
    transfer_table("db1", "db2", "sc.tb1", "sc.tb2")
  )
  expect_equal(get_status(res), "succeeded")
})

# utils functions -------------------------------------------------------------

test_that("multipart_upload returns file_id", {
  fn <- tempfile()
  d <- data.frame(a = 1:5, b = 5:1)
  write.csv(d, fn, row.names = FALSE)
  id <- with_mock(
    `civis::upload_one` = function(...) NULL,
    `civis::files_post_multipart` = function(...) list(id = 1, uploadUrls = "url"),
    `future::value` = function(...) NULL,
    `civis::files_post_multipart_complete` = function(...) NULL,
    multipart_upload(fn, name = "asdf")
  )
  expect_equal(id, 1)
})

test_that("write_chunks splits files", {
  # csv
  d <- data.frame(a = 1:5, b = 5:1)
  fn <- tempfile(fileext = ".txt")
  write.csv(d, fn, row.names = FALSE)
  fl <- write_chunks(fn, chunk_size = file.size(fn)/4)
  expect_equal(length(fl), 4)

  the_text <- paste0(unlist(lapply(fl, function(f) {
    readChar(f, file.size(f))
  })), collapse = "")
  ans <- read.csv(textConnection(the_text))
  expect_equal(ans, d)

  # rds; again, we have to really just stitch the files together to read it back.
  fn <- tempfile(fileext = ".rds")
  saveRDS(d, fn)
  fl <- write_chunks(fn, chunk_size = file.size(fn)/4)

  the_bin <- unlist(lapply(fl, function(f) {
    readBin(f, what = "raw", file.size(f))
  }))
  zz <- rawConnection(the_bin)
  ans <- readRDS(gzcon(zz))
  close(zz)
  expect_equal(ans, d)
})

test_that("get_db returns default database or an error", {
  expect_equal(get_db("sea_creatures"), "sea_creatures")

  msg <- c("Argument database is NULL and options(\"civis.default_db\") not set. Set this option using options(civis.default_db = \"my_database\")")
  test_msg <- with_mock(
    `civis::get_default_database` = function(...) NULL,
    tryCatch(get_db(NULL), error = function(e) e$message)
  )
  expect_equal(msg, test_msg)

  options(civis.default_db = "sea_creatures")
  expect_equal(get_db(NULL), "sea_creatures")
})

test_that("delimiter_name_from_string catches bad input", {
  e <- "Delimiter must be one of ',', '|', '\t'"
  comma <- delimiter_name_from_string(",")
  pipe <- delimiter_name_from_string("|")
  tab <- delimiter_name_from_string("\t")
  expect_equal(comma, "comma")
  expect_equal(pipe, "pipe")
  expect_equal(tab, "tab")
  expect_error(delimiter_name_from_string(":"), e)
})

test_that("start_import_job parses table correctly", {
  with_mock(
    `civis::get_database_id` = function(...) -999,
    `civis::default_credential` = function(...) "fake",
    `civis::imports_post_files` = function(...) {
      args <- list(...)
      list(schema = args[[1]], table = args[[2]])
    },
    expect_equal(
      start_import_job("mockdb", "mock.table", if_exists = "append",
                       NULL, NULL, NULL, NULL, NULL, NULL),
      list(schema = "mock", table = "table")
    )
  )
})

test_that("start_import_job checks if_exists value", {
  error_msg <- 'if_exists must be set to "fail", "truncate", "append", or "drop"'
  with_mock(
    `civis::get_database_id` = function(...) -999,
    `civis::default_credential` = function(...) "fake",
    `civis::imports_post_files` = function(...) {
      args <- list(...)
      list(schema = args[[1]], table = args[[2]])
    },
    expect_error(
      start_import_job("mockdb", "mock.table", if_exists = "do nothing",
                       NULL, NULL, NULL, NULL),
      error_msg
    )
  )
})

test_that("download_script_results returns sensible errors", {
  error <- "Query produced no output. \\(script_id = 561, run_id = 43\\)"
  mock_get_run <- function(script_id, run_id) list(script_id = script_id, run_id = run_id)
  with_mock(
    `civis::scripts_get_sql_runs` = mock_get_run,
    expect_error(download_script_results(561, 43, "some_file"), error)
  )
})
