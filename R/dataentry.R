#' \code{ParseEnteredData}
#' @description Takes a raw character matrix returned by dataEntry R GUI control
#' and attempts to parse it to something more friendly such as a numeric matrix.
#' @param raw.matrix Character matrix
#' @param warn Whether to show warnings
#' @param want.data.frame Whether to return a data frame instead of a matrix or vector.
#' @param want.factors Whether a text variable should be converted to a factor in a data frame.
#' @param want.col.names Whether to interpret the first row as column names in a data frame.
#' @param want.row.names Whether to interpret the first col as row names in a data frame.
#' @param us.format Whether to use the US convention when parsing dates in a data frame.
#' @export
ParseEnteredData <- function(raw.matrix, warn = TRUE, want.data.frame = FALSE, want.factors = TRUE,
                             want.col.names = TRUE, want.row.names = FALSE, us.format = TRUE)
{
    if (all(raw.matrix == ""))
        stop("No data has been entered.")

    m <- removeEmptyRowsAndColumns(raw.matrix, !want.data.frame)
    if (want.data.frame)
        parseAsDataFrame(m, warn, want.factors, want.col.names, want.row.names, us.format)
    else
        parseAsVectorOrMatrix(m, warn)
}

isTextNumeric <- function(t)
{
    all(!is.na(suppressWarnings(asNumericWithPercent(t))) | t == "")
}

isNumericMatrixWithLabelsAndTitles <- function(m)
{
    n.row <- nrow(m)
    n.col <- ncol(m)
    result <- n.row >= 3 && n.col >= 3 && m[3, 1] != "" && m[1, 3] != "" && all(m[1:2, 1:2] == "") && isTextNumeric(m[3:n.row, 3:n.col])
    if (n.row > 3)
        result <- result && m[4:n.row, 1] == ""
    if (n.col > 3)
        result <- result && m[1, 4:n.col] == ""
    result
}

asNumericWithPercent <- function(t)
{
    v <- as.vector(t)
    result <- suppressWarnings(as.numeric(v))
    ind <- is.na(result) & grepl("%$", v)
    result[ind] <- suppressWarnings(as.numeric(gsub("%$", "", v[ind]))) / 100
    result
}

# Remove first few rows and columns if they are empty
removeEmptyRowsAndColumns <- function(m, drop)
{
    start.row <- 1
    for (i in 1:nrow(m))
        if (all(m[i, ] == ""))
            start.row <- i + 1
        else
            break
        start.col <- 1
        for (i in 1:ncol(m))
            if (all(m[, i] == ""))
                start.col <- i + 1
            else
                break
    m[start.row:nrow(m), start.col:ncol(m), drop = drop]
}

parseAsVectorOrMatrix <- function(m, warn)
{
    n.row <- nrow(m)
    n.col <- ncol(m)

    if (isTextNumeric(m))
    {
        if (is.vector(m))
            result <- asNumericWithPercent(m) # numeric vector, without names
        else
            result <- matrix(asNumericWithPercent(m), nrow = n.row) # numeric matrix, without names
    }
    else if (is.vector(m)) # character vector
        result <- m
    else if (n.col == 2 && isTextNumeric(m[, 2])) # numeric vector with names
        result <- structure(asNumericWithPercent(m[, 2]), names = m[, 1])
    else if (isTextNumeric(m[2:n.row, 2:n.col])) # numeric matrix with names
    {
        numeric.m <- matrix(asNumericWithPercent(m[2:n.row, 2:n.col, drop = FALSE]), nrow = n.row - 1)
        if (any(m[1, 2:n.col] != ""))
            colnames(numeric.m) <- m[1, 2:n.col]
        if (any(m[2:n.row, 1] != ""))
            rownames(numeric.m) <- m[2:n.row, 1]
        if (any(m[1, 1] != ""))
            attr(numeric.m, "statistic") <- m[1, 1]
        result <- numeric.m
    }
    else if (isNumericMatrixWithLabelsAndTitles(m)) # numeric matrix with row and column names and titles
    {
        numeric.m <- matrix(asNumericWithPercent(m[3:n.row, 3:n.col, drop = FALSE]), nrow = n.row - 2)
        if (any(m[2, 3:n.col] != ""))
            colnames(numeric.m) <- m[2, 3:n.col]
        if (any(m[3:n.row, 2] != ""))
            rownames(numeric.m) <- m[3:n.row, 2]
        if (any(m[2, 2] != ""))
            attr(numeric.m, "statistic") <- m[2, 2]
        attr(numeric.m, "row.column.names") <- c(m[3, 1], m[1, 3]) # titles
        result <- numeric.m
    }
    else # character matrix
    {
        if (warn)
            warning("The entered data could not be interpreted.")
        result <- m
    }
    result
}

parseAsDataFrame <- function(m, warn = TRUE, want.factors = FALSE, want.col.names = TRUE, want.row.names = FALSE,
                             us.format = TRUE)
{
    n.row <- nrow(m)
    n.col <- ncol(m)

    if (want.col.names && n.row == 1)
        stop("There is no data to display as there is only one row in the entered data,
             and the column names option has been selected.")
    if (want.row.names && n.col == 1)
        stop("There is no data to display as there is only one column in the entered data,
             and the row names option has been selected.")

    start.row <- if (want.col.names) 2 else 1
    start.col <- if (want.row.names) 2 else 1

    df <- data.frame(m[start.row:n.row, start.col:n.col], stringsAsFactors = FALSE)
    if (want.col.names)
    {
        col.names <- m[1, start.col:n.col]
        colnames(df) <- col.names
        if (warn && any(col.names == ""))
            warning("Some variables have been assigned blank names.")
        else if (warn && length(unique(col.names)) < length(col.names))
            warning("Some variables share the same name.")
    }
    else
        colnames(df) <- paste0("X", 1:(n.col - start.col + 1))
    if (want.row.names)
        rownames(df) <- m[start.row:n.row, 1]

    n.var <- ncol(df)
    for (i in 1:n.var)
    {
        v <- df[[i]]
        if (isTextNumeric(v))
            df[[i]] <- asNumericWithPercent(v) # numeric
        else
        {
            parsed.dates <- ParseDateTime(v, us.format)
            if (!any(is.na(parsed.dates)))
                df[[i]] <- parsed.dates # date
            else if (want.factors)
                df[[i]] <- as.factor(v) # factor
            else
                df[[i]] <- v # character
        }
    }
    df
}