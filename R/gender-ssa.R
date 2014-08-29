#' Find the gender of first names using Social Security data
#'
#' This internal function implements the \code{method = "ssa"} option of
#' \code{\link{gender}}. See that function for documentation.
#'
#' @param name A character string of a first name. Case insensitive.
#' @param years This argument can be either a single year or a range of years in
#'   the form \code{c(1880, 1900)}. If no value is specified, then the names
#'   will be looked up for the period 1932 to 2012. If a year or range of years
#'   is specified, then the names will be looked up for that period. Dates may
#'   range from 1880 to 2012. For years before 1930, the IPUMS method is
#'   probably better.
#' @param certainty A boolean value, which determines whether or not to return
#'   the proportion of male and female uses of names in addition to determining
#'   the gender of names.
#' @param correct_skew A boolean value which determines whether or not to
#'   correct the skewed gender ratios of the SSA data. Default is to do the
#'   correction, which is recommended.
gender_ssa <- function(name, years, certainty, correct_skew = TRUE) {

  # If we're going to correct the skew, calculate the correction factors;
  # otherwise just give them a value of one.
  if (correct_skew) {
    correx <- get_correction_factors(years)
  } else {
    correx <- c(1, 1); names(correx) <- c("female", "male")
  }

  # An internal function to predict the gender of one name
  apply_ssa <- function(name_to_lookup) {

    # Calculate the male and female proportions for the given range of years
    results <- babynames::babynames %>%
      dplyr::filter(tolower(name) == tolower(name_to_lookup),
             year >= years[1], year <= years[2])

    # If the name isn't in the data set, use that information rather than
    # silently dropping a row
    if (nrow(results) == 0) {
      results <- data.frame(name = name_to_lookup,
                            female = NA,
                            male = NA,
                            proportion_male = NA,
                            proportion_female = NA)
    } else {
      # Reshaping from babynames format to our assumed format
      results <-
        results %>%
        dplyr::select(-prop) %>%
        tidyr::spread(sex, n)

      if(!"F" %in% names(results)) results$F <- NA
      if(!"M" %in% names(results)) results$M <- NA

      results <- results %>%
        dplyr::select(name, year, male = M, female = F)
    }

    results <- results %>%
      group_by(name) %>%
      # Multiply the number of males and females by the correction factors
      summarise(female = sum(female, na.rm = TRUE) * correx['female'],
                male = sum(male, na.rm = TRUE) * correx['male']) %>%
      mutate(proportion_male = round((male / (male + female)), digits = 4),
             proportion_female = round((female / (male + female)), digits = 4)) %>%
      # Now predict the gender
      mutate(gender = ifelse(proportion_female == 0.5, "either",
                             ifelse(proportion_female > 0.5, "female", "male")))

    # Delete the male and female columns since we won't report them to the user.
    # Under no circumstances would we want to report these values to the user:
    # since we have corrected them to get an even gender ratio, so they no
    # longer represent the raw number of names for a given range of years.
    results <- results %>% select(-male, -female)

    # Delete the certainty columns unless the user wants them
    if(!certainty) results <- results %>% select(-proportion_male, -proportion_female)

    # Include the years used in the data frame
    results <- results %>% mutate(year_min = years[1], year_max = years[2])

    # Use the original capitalization of the name
    results$name <- name_to_lookup

    return(as.list(results))

  }

  # Use the function directly if there is one name; use lapply if there are > 1.
  # Return the results as a list or a list of lists.
  if (length(name) == 1) {
    return(as.list(apply_ssa(name)))
  } else {
    return(as.list(lapply(name, apply_ssa)))
  }

}

#' Calculate the correction factors for a year or range of years
#'
#' The SSA data is skewed by gender, especially for years before 1935. This
#' internal function figures out the factor by which the gender ratio should be
#' multiplied in order to assume that the ratio of male to female births for
#' those years was 1:1.
#'
#' @param years The range of years. This value will be passed to it by the
#'   gender_ssa function.
#' @param names_df The data frame of names and genders used inside the function.
#'   Defaults to the U.S. Social Security Administration's database of baby
#'   names provided by the \code{babynames} package.
get_correction_factors <- function(years) {
  selection <- babynames::babynames %>%
    dplyr::filter(year >= years[1], year <= years[2]) %>%
    dplyr::select(-prop) %>%
    tidyr::spread(sex, n) %>%
    dplyr::select(name, year, female = F, male = M)

  ratio_female <- sum(selection$female, na.rm = TRUE) /
    sum(selection$female + selection$male, na.rm = TRUE)
  ratio_male   <- 1 - ratio_female

  correction_factors <- c(0.5 / ratio_female, 0.5 / ratio_male)
  names(correction_factors) <- c("female", "male")
  return(correction_factors)
}
