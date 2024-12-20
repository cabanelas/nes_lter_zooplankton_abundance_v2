################################################################################
#############     Zooplankton Abundance DATA Update EDI v2     #################
#############             Abundance calculations               #################
#############             AUG-2024                             #################
## by: Alexandra Cabanelas 
################################################################################

#calculate 100m3 and 10m2 zooplankton abundance 
# for zooplankton collected during NES LTER transect cruises 

#100m3 = ((zoo_aliquot*ZOO_STAGE_COUNT)/gear_volume_filtered)*100))*1/sample_split_factor
#10m2 = ((zoo_aliquot*ZOO_STAGE_COUNT*net_max_depth_m)/gear_volume_filtered)*10))*1/sample_split_factor

# already calculated volume sampled - so get that from metadata inventory (inventory package)

## ------------------------------------------ ##
#            Packages -----
## ------------------------------------------ ##
library(here)
library(tidyverse)
library(suncalc)

## ------------------------------------------ ##
#            Data -----
## ------------------------------------------ ##
metadata <- read.csv(file.path("raw",
                               "nes-lter-zooplankton-tow-metadata-v2.csv"),
                     header = T) #from zooplankton inventory package
zoop <- read.csv(file.path("output",
                           "all_zoop_count_data.csv"),
                 header = T) #created in merge_data.R 

## ------------------------------------------ ##
#            Tidy -----
## ------------------------------------------ ##

# delete CONC columns - to keep just counts
# will recalculate zoop concentration/abundances using volume from metadata file
# those volume sampled have been checked and corrected
zoop <- zoop %>%
  dplyr::select(CRUISE_NAME, STATION, CAST, SAMPLE_SPLIT_FACTOR, EVENT_DATE, TIME, 
                DAY, MONTH, YEAR, HOUR, MINUTE, VOLUME_100M3, ZOO_ALIQUOT, 
                TAXA_004, TAXA_NAME, ITIS_TAXON, 
                ITIS_TSN, CONC_100M3, ZOOPLANKTON_COUNT, TOTCNT, ZOO_STAGE_000,
                ZOO_STAGE_024, ZOO_STAGE_023, ZOO_STAGE_022, ZOO_STAGE_021, 
                ZOO_STAGE_020, ZOO_STAGE_030, ZOO_STAGE_029, ZOO_STAGE_028, 
                ZOO_STAGE_013, ZOO_STAGE_999, PRIMARY_FLAG, SECONDARY_FLAG)

# add L to station column
zoop <- zoop %>%
  mutate(STATION = if_else(STATION %in% c("MVCO", "u11c"), 
                           STATION, 
                           paste0("L", STATION)))

# remove spaces CRUISE_NAME column
unique(zoop$CRUISE_NAME)
zoop$CRUISE_NAME <- str_replace_all(zoop$CRUISE_NAME, " ", "")
unique(zoop$CRUISE_NAME)

# make col names lowercase
names(zoop) <- tolower(names(zoop))

zoop <- zoop %>%
  rename(cruise = cruise_name,
         volume_ml = volume_100m3)

colnames(zoop)

## add missing data to zp data (from the metadata file)
#en627 needs cast and date info and flags

# date
metadata <- metadata %>%
  mutate(date_start_UTC = format(dmy(date_start_UTC), "%d-%b-%y"))

metadata_select <- metadata %>%
  select(cruise, station, cast, date_start_UTC, time_start_UTC, net_max_depth_m,
         vol_filtered_m3_335, primary_flag, secondary_flag)

#EN655 L7 B11 sample was from 150 net
# so I'm manually updating the volume so it is correct for other calculations
metadata_select$vol_filtered_m3_335[metadata_select$cruise == "EN655" &
                                      metadata_select$station == "L7" &
                                      metadata_select$cast == 11] <- 159.9276

# EN627 need flags - get it from metadata df 

zoop <- zoop %>%
  left_join(metadata_select %>% filter(cruise == "EN627"), 
            by = c("cruise", "station"), 
            suffix = c("", "_en627")) 

zoop <- zoop %>%
  mutate(
    # fill cast, event_date, and time specifically for EN627 
    cast = ifelse(cruise == "EN627" & is.na(cast), cast_en627, cast),
    event_date = ifelse(cruise == "EN627" & is.na(event_date), 
                        date_start_UTC, event_date),
    time = ifelse(cruise == "EN627" & is.na(time), time_start_UTC, time),
    primary_flag = ifelse(cruise == "EN627" & is.na(primary_flag), primary_flag_en627, primary_flag),
    secondary_flag = ifelse(cruise == "EN627" & is.na(secondary_flag), secondary_flag_en627, secondary_flag)
  ) %>%
  # remove temporary columns for EN627
  dplyr::select(-cast_en627, -date_start_UTC, -time_start_UTC, 
                -net_max_depth_m, -vol_filtered_m3_335, -primary_flag_en627, 
                -secondary_flag_en627)

# add net max depth and vol_filtered_m3_335 from metadata_select to zoop
zoop <- zoop %>%
  left_join(metadata_select %>% select(cruise, station, cast, 
                                       net_max_depth_m, vol_filtered_m3_335), 
            by = c("cruise", "station", "cast"))

# need to add sample split factor for en627
# manually checked and all are == 0.75
zoop <- zoop %>%
  mutate(sample_split_factor = ifelse(cruise == "EN627", 0.75, sample_split_factor))

# need to add isopoda taxa code == 2200 (missing for EN649 L3)
zoop <- zoop %>%
  mutate(taxa_004 = ifelse(is.na(taxa_004) & taxa_name == "Isopoda", 
                           2200, 
                           taxa_004))

# AR63 L5 B2 doesnt have volume filtered due to not enough data from 
#this cruise to calculate
zoop <- zoop %>%
  mutate(
    primary_flag = case_when(
      cruise == "AR63" & 
        station == "L5" & 
        cast == 2 ~ 3,
      TRUE ~ primary_flag  # keep existing values otherwise
    ),
    secondary_flag = case_when(
      cruise == "AR63" & 
        station == "L5" & 
        cast == 2 ~ "Volume filtered could not be calculated so abundances are unavailable for this tow. Raw counts are available.",
      TRUE ~ secondary_flag  
    )
  )

zoop <- zoop %>%
  rename(taxa_code = taxa_004)

#spelling of taxa is inconsistent - sometimes all caps, etc...
capitalize_first_word <- function(x) {
  paste(toupper(substring(x, 1, 1)), tolower(substring(x, 2)), sep = "")
}
# apply the function to taxa_name column
zoop$taxa_name <- sapply(zoop$taxa_name, capitalize_first_word)

#this creates a duplicate entry for two samples (due to capitalized spelling in original)
zoop %>%
  count(cruise, station, cast, taxa_name) %>%
  filter(n > 1)

# remove the duplicate
zoop <- zoop %>%
  filter(
    !(
      (cruise == "EN644" & station == "L9" & cast == 18 & taxa_name == "Heteropoda") |
        (cruise == "EN657" & station == "L1" & cast == 1 & taxa_name == "Cumacea")
    ) |
      zooplankton_count > 0 # Retain rows with count > 0 for these cases
  )

#fix taxa names
zoop <- zoop %>%
  # fix misspellings
  mutate(taxa_name = case_when(
    taxa_name == "Brachiiopoda" ~ "Brachiopoda",  
    taxa_name %in% c("Calausocalanidae", "Clausocalanoidae") ~ "Clausocalanidae",
    taxa_name == "Calocalanus tnuis" ~ "Calocalanus tenuis",
    taxa_name == "Centropages bradygi" ~ "Centropages bradyi",
    taxa_name == "Echinoderemata" ~ "Echinodermata",
    taxa_name %in% c("Haeterorhabdidae","Heterorhadbidae") ~ "Heterorhabdidae",
    taxa_name == "Hyperidea" ~ "Hyperiidea",
    #taxa_name == "Gammaridea" ~ "Gammaridae",
    taxa_name == "Lucciutia" ~ "Lucicutia", 
    taxa_name == "Lucifer spp." ~ "Lucifer", 
    taxa_name == "Metrididae" ~ "Metridiidae",
    taxa_name == "Micorcalanus" ~ "Microcalanus",
    taxa_name == "Mysidopsis begelowi" ~ "Mysidopsis bigelowi", 
    taxa_name == "Mysidacea" ~ "Mysida", 
    taxa_name == "Pseudodiaptomis" ~ "Pseudodiaptomus",
    taxa_name == "Phoennidae" ~ "Phaennidae", # typo? this is what i think
    taxa_name == "Oikopleura spp." ~ "Oikopleura",
    taxa_name == "Scolecithricidae" ~ "Scolecitrichidae",
    taxa_name == "Tomoptems" ~ "Tomopteris", # typo? this is what i think
    taxa_name %in% c("Unidentified plankton and fragments",
                     "Unidentified zooplankton") ~ "Unidentified Plankton", 
    TRUE ~ taxa_name  #keep all other names as they are
  ))
taxa_name <- zoop %>% distinct(taxa_name)
#write.table(taxa_name, file = "taxanames.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)
#data <- read_delim("taxanames.csv", delim = "|")
#write.csv(data, "zptaxanames_ITIS_taxamatchreport.csv")

# fix taxa_codes (found typos/inconsistencies)
zoop <- zoop %>%
  mutate(
    taxa_code = case_when(
      taxa_name == "Heterorhabdidae" ~ 4030,
      taxa_name == "Amphipoda" ~ 400,
      taxa_name == "Augaptilidae" ~ 4182,
      taxa_name == "Isopoda" ~ 2200,
      taxa_name == "Ctenocalanus" ~ 4278,
      taxa_name == "Stomatopoda" ~ 3200,
      TRUE ~ taxa_code # keep original values for other taxa
    )
  )

# rename columns
colnames(zoop)
zoop <- zoop %>%
  rename(adult_count = zoo_stage_000,
         c5_count = zoo_stage_024,
         c4_count = zoo_stage_023, 
         c3_count = zoo_stage_022,
         c2_count = zoo_stage_021,
         c1_count = zoo_stage_020,
         cryptopia_count = zoo_stage_030,
         furcilia_count = zoo_stage_029,
         calyptopis_count = zoo_stage_028,
         nauplius_count = zoo_stage_013,
         unknown_count = zoo_stage_999)

## ------------------------------------------ ##
#            DAY VS NIGHT -----
## ------------------------------------------ ##
# 1: add coordinates from metadata to zoop
metadata_subset <- metadata[, c("cruise", "station", "cast", "lat_start", "lon_start")]

zoop <- merge(zoop, metadata_subset, by = c("cruise", "station", "cast"), 
              all.x = TRUE)

zoop <- zoop %>%
  rename(lat = lat_start,
         lon = lon_start)

# coordinates for AR63 L5 missing - so give it fixed station coordinates
# 40.5133	-70.8833
zoop <- zoop %>%
  mutate(
    lat = if_else(cruise == "AR63" & station == "L5", 40.5133, lat),
    lon = if_else(cruise == "AR63" & station == "L5", -70.8833, lon)
  )

# 2: create date-time column
zoop <- zoop %>%
  mutate(datetime_utc = as.POSIXct(paste(event_date, time), 
                                   format="%d-%b-%y %H:%M:%S", tz="UTC"))

# 3: suntools

determine_day_night_suncalc <- function(datetime_utc, 
                                        lat, lon, 
                                        definition = "sunrise_sunset") {
  # convert UTC datetime to local Eastern Time
  datetime_et <- with_tz(datetime_utc, tzone = "America/New_York")
  
  # extract the date for sunlight times calculation
  date_et <- as.Date(datetime_et)
  
  # get sunlight times
  sunlight_times <- getSunlightTimes(date = date_et, 
                                     lat = lat, lon = lon, 
                                     keep = c("sunrise", "sunset", 
                                              "dawn", "dusk", 
                                              "nauticalDawn", "nauticalDusk"))
  
  # you can choose different definitions later 
  if (definition == "sunrise_sunset") {
    if (datetime_et >= sunlight_times$sunrise & datetime_et < sunlight_times$sunset) {
      return("Day")
    } else {
      return("Night")
    }
  } else if (definition == "dawn_dusk") {
    if (datetime_et >= sunlight_times$dawn & datetime_et < sunlight_times$dusk) {
      return("Day")
    } else {
      return("Night")
    }
  } else if (definition == "nautical") {
    if (datetime_et >= sunlight_times$nauticalDawn & datetime_et < sunlight_times$nauticalDusk) {
      return("Day")
    } else {
      return("Night")
    }
  } else {
    stop("Invalid definition")
  }
}


zoop <- zoop %>%
  rowwise() %>%
  mutate(day_night = determine_day_night_suncalc(datetime_utc, 
                                                 lat, lon, 
                                                 definition = "sunrise_sunset")) %>%
  ungroup()

zoop %>%
  mutate(hour = lubridate::hour(with_tz(datetime_utc, 
                                        tzone = "America/New_York"))) %>%
  ggplot(aes(x = hour, fill = day_night)) +
  geom_histogram(binwidth = 1, position = "dodge") +
  labs(x = "Hour of Day (Local Time)", 
       y = "Count") +
  scale_fill_manual(values = c("Day" = "skyblue", 
                               "Night" = "darkblue"))

zoop %>%
  count(day_night) %>%
  mutate(proportion = n / sum(n))

## ------------------------------------------ ##
#     make sure all taxa are present -----
## ------------------------------------------ ##
# sometimes taxa == 0 but other times they are just not included..
# make sure all cruises have the 138 taxa with 0s accordingly 
zoop %>%
  group_by(cruise, station, cast) %>%
  summarise(row_count = n()) %>%
  arrange(cruise, station, cast) #the row count should be the same

zoop %>%
  distinct(cruise, station, cast) %>%
  count() #170*138
#final df should have 23460 rows

# step 1: unique cruise, station, and cast 
unique_cruise_stations <- zoop %>%
  distinct(cruise, station, cast)

# step 2: expand taxa within each cruise-station-cast combination
unique_combinations <- unique_cruise_stations %>%
  cross_join(tibble(taxa_name = unique(zoop$taxa_name)))

# step 3: Join with the original dataset and fill missing values
zoop <- unique_combinations %>%
  left_join(zoop, by = c("cruise", "station", "cast", "taxa_name")) %>%
  mutate(across(starts_with("conc_"), ~ coalesce(.x, 0))) %>%
  mutate(across(ends_with("_count"), ~ coalesce(.x, 0)))

cols_to_fill <- c(
  "sample_split_factor", "event_date", "time", "day", "month",
  "year", "hour", "minute", "volume_ml", "zoo_aliquot", 
  "totcnt", "primary_flag", "secondary_flag", "net_max_depth_m",
  "vol_filtered_m3_335", "lat", "lon", "datetime_utc", "day_night"
)

zoop <- zoop %>%
  group_by(cruise, station, cast) %>%
  fill(all_of(cols_to_fill), .direction = "downup") %>% 
  ungroup()

# step 4: add taxa_code - lookup table 
taxa_lookup <- zoop %>%
  select(taxa_name, taxa_code) %>%
  filter(!is.na(taxa_code)) %>% 
  distinct() 

zoop <- zoop %>%
  left_join(taxa_lookup, by = "taxa_name", suffix = c("", "_lookup")) %>% 
  mutate(
    taxa_code = coalesce(taxa_code, taxa_code_lookup) 
  ) %>%
  select(-taxa_code_lookup)

## ------------------------------------------ ##
#            Calculate 100m3 abundances -----
## ------------------------------------------ ##
#100m3 = ((zoo_aliquot*ZOO_STAGE_COUNT)/gear_volume_filtered)*100))*1/sample_split_factor
#concentration of zooplankton = individuals per 100 cubic meters

zoop_100m3 <- zoop %>%
  mutate(
    # standard haul factor
    # h = 100 / v where: v = volume of water filtered (in meters cubed)
    haul_factor = 100 / vol_filtered_m3_335,
    
    conc_100m3 = ((zoo_aliquot * zooplankton_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    
    adult_100m3 = ((zoo_aliquot * adult_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    c5_100m3 = ((zoo_aliquot * c5_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    c4_100m3 = ((zoo_aliquot * c4_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    c3_100m3 = ((zoo_aliquot * c3_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    c2_100m3 = ((zoo_aliquot * c2_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    c1_100m3 = ((zoo_aliquot * c1_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    cryptopia_100m3 = ((zoo_aliquot * cryptopia_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    furcilia_100m3 = ((zoo_aliquot * furcilia_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    calyptopis_100m3 = ((zoo_aliquot * calyptopis_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    nauplius_100m3 = ((zoo_aliquot * nauplius_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor),
    unknown_100m3 = ((zoo_aliquot * unknown_count) / vol_filtered_m3_335) * 100 * (1 / sample_split_factor)
  )

# select final columns 
zoop_100m3 <- zoop_100m3 %>%
  select(cruise, station, cast, datetime_utc, day_night, sample_split_factor, 
         volume_ml, zoo_aliquot, haul_factor, taxa_code, taxa_name, conc_100m3, 
         zooplankton_count, totcnt, adult_count, c5_count, c4_count, c3_count, 
         c2_count, c1_count, cryptopia_count, furcilia_count, calyptopis_count, 
         nauplius_count, unknown_count, adult_100m3, c5_100m3, c4_100m3, c3_100m3,
         c2_100m3, c1_100m3, cryptopia_100m3, furcilia_100m3, 
         calyptopis_100m3, nauplius_100m3, unknown_100m3,
         primary_flag, secondary_flag)

colnames(zoop_100m3)
staged_100m3 <- zoop_100m3

## ------------------------------------------ ##
#            Calculate 10m2 abundances -----
## ------------------------------------------ ##
# calculate areal abundance 10m2
#abundances per 10 square meters
#10m2 = ((zoo_aliquot*ZOO_STAGE_COUNT*net_max_depth_m)/gear_volume_filtered)*10))*1/sample_split_factor

# standard haul factor 
# h = z * 10 / v
#where: z = maximum tow depth (in meters)
#v = volume of water filtered (in meters cubed)

zoop_10m2 <- zoop %>%
  mutate(
    haul_factor = net_max_depth_m * 10 / vol_filtered_m3_335,
    
    conc_10m2 = ((zoo_aliquot * zooplankton_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    
    adult_10m2 = ((zoo_aliquot * adult_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    c5_10m2 = ((zoo_aliquot * c5_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    c4_10m2 = ((zoo_aliquot * c4_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    c3_10m2 = ((zoo_aliquot * c3_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    c2_10m2 = ((zoo_aliquot * c2_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    c1_10m2 = ((zoo_aliquot * c1_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    cryptopia_10m2 = ((zoo_aliquot * cryptopia_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    furcilia_10m2 = ((zoo_aliquot * furcilia_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    calyptopis_10m2 = ((zoo_aliquot * calyptopis_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    nauplius_10m2 = ((zoo_aliquot * nauplius_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor),
    unknown_10m2 = ((zoo_aliquot * unknown_count * net_max_depth_m) / vol_filtered_m3_335) * 10 * (1 / sample_split_factor)
  )

# select final columns 
zoop_10m2 <- zoop_10m2 %>%
  select(cruise, station, cast, datetime_utc, day_night, sample_split_factor, 
         volume_ml, zoo_aliquot, haul_factor, taxa_code, taxa_name, 
         conc_10m2, zooplankton_count, totcnt, adult_count, c5_count, c4_count,
         c3_count, c2_count, c1_count, cryptopia_count, furcilia_count, 
         calyptopis_count, nauplius_count, unknown_count, adult_10m2, 
         c5_10m2, c4_10m2, c3_10m2, c2_10m2, c1_10m2, cryptopia_10m2, 
         furcilia_10m2, calyptopis_10m2, nauplius_10m2, unknown_10m2,
         primary_flag, secondary_flag)

colnames(zoop_10m2)
staged_10m2 <- zoop_10m2

## ------------------------------------------ ##
#            UNSTAGED -----
## ------------------------------------------ ##

## ---------------------- ##
#        100m3 -----
## ---------------------- ##
unstaged_100m3 <- zoop_100m3 %>%
  select(-c(adult_count:unknown_100m3))

# wide format - concentration only, no counts
wide_unstaged_100m3 <- unstaged_100m3 %>%
  group_by(cruise, station, cast) %>%
  pivot_wider(
    names_from = taxa_name,      # taxa_name as column names
    values_from = conc_100m3,    # conc_100m3 values 
    values_fill = 0              # fill NAs with 0 
  ) %>%
  dplyr::select(-taxa_code, -zooplankton_count) %>%
  # after pivoting, consolidate rows for each taxon column
  # summarize(across(everything(), ~ max(.)), .groups = "drop")
  summarize(across(everything(), ~ .[. != 0][1]), .groups = "drop") %>%
  # replace NAs with 0 in specified columns
  mutate(across(`Calanus finmarchicus`:`Temoropia mayumbaensis`, ~ replace_na(., 0)))

# add _ between taxa name columns so there arent any spaces 
colnames(wide_unstaged_100m3) <- gsub(" ", "_", colnames(wide_unstaged_100m3))

## ---------------------- ##
#        10m2 -----
## ---------------------- ##
unstaged_10m2 <- zoop_10m2 %>%
  select(-c(adult_count:unknown_10m2))

# wide format - concentration only, no counts
wide_unstaged_10m2 <- unstaged_10m2 %>%
  group_by(cruise, station, cast) %>%
  pivot_wider(
    names_from = taxa_name,     # taxa_name as column names
    values_from = conc_10m2,    # conc_10m2 values 
    values_fill = 0             # fill NAs with 0 
  ) %>%
  dplyr::select(-taxa_code, -zooplankton_count) %>%
  # after pivoting, consolidate rows for each taxon column
  summarize(across(everything(), ~ .[. != 0][1]), .groups = "drop") %>%
  mutate(across(`Calanus finmarchicus`:`Temoropia mayumbaensis`, ~ replace_na(., 0)))

# add _ between taxa name columns so there arent any spaces 
colnames(wide_unstaged_10m2) <- gsub(" ", "_", colnames(wide_unstaged_10m2))

## ------------------------------------------ ##
#     order data in ascending date order -----
## ------------------------------------------ ##

# first need to change date from character to date class
sort_by_event_date <- function(df) {
  df %>%
    arrange(datetime_utc) %>%  # sort by date
    mutate(datetime_utc = as.character(datetime_utc)) 
}

# apply the function to all data frames
staged_10m2 <- sort_by_event_date(staged_10m2)
staged_100m3 <- sort_by_event_date(staged_100m3)
unstaged_10m2 <- sort_by_event_date(unstaged_10m2)
unstaged_100m3 <- sort_by_event_date(unstaged_100m3)
wide_unstaged_10m2 <- sort_by_event_date(wide_unstaged_10m2)
wide_unstaged_100m3 <- sort_by_event_date(wide_unstaged_100m3)

## ------------------------------------------ ##
#            Filter staged df -----
## ------------------------------------------ ##

staged_10m2_v2 <- staged_10m2


# staged columns
staged_columns <- c("adult_count", "c5_count", "c4_count", "c3_count", 
                    "c2_count", "c1_count", "cryptopia_count", "furcilia_count", 
                    "calyptopis_count", "nauplius_count","unknown_count")

# filter for taxa with any staged data greater than 0
staged_species <- staged_10m2_v2 %>%
  filter(if_any(all_of(staged_columns), ~ . > 0)) %>%
  distinct(taxa_name) %>%
  pull(taxa_name)

staged_species

# filter for those - keep only staged taxa
staged_10m2_v2 <- staged_10m2_v2 %>%
  filter(taxa_name %in% staged_species)

staged_100m3_v2 <- staged_100m3

staged_100m3_v2 <- staged_100m3_v2 %>%
  filter(taxa_name %in% staged_species)

## ------------------------------------------ ##
#            QA/QC zoop data -----
## ------------------------------------------ ##

data_frames <- list(staged_10m2_v2, staged_100m3_v2, 
                    unstaged_10m2, unstaged_100m3, 
                    wide_unstaged_10m2, wide_unstaged_100m3)
df_names <- c("nes-lter-zp-abundance-335um-staged10m2",
              "nes-lter-zp-abundance-335um-staged100m3",
              "nes-lter-zp-abundance-335um-unstaged10m2",
              "nes-lter-zp-abundance-335um-unstaged100m3",
              "nes-lter-zp-abundance-335um-wide-unstaged10m2",
              "nes-lter-zp-abundance-335um-wide-unstaged100m3")

#################################################

colnames(unstaged_10m2)
str(unstaged_10m2)
sapply(unstaged_10m2, class)

unique(unstaged_10m2$cruise)
unique(unstaged_10m2$station)
unique(unstaged_10m2$cast)
unique(unstaged_10m2$sample_split_factor)
unique(unstaged_10m2$zoo_aliquot)
unique(unstaged_10m2$taxa_name)
unique(unstaged_10m2$primary_flag)
unique(unstaged_10m2$secondary_flag)

unstaged_10m2 %>%
  summarise(
    min_ssp = min(sample_split_factor , na.rm = TRUE),
    max_ssp = max(sample_split_factor , na.rm = TRUE),
    min_vol = min(volume_ml, na.rm = TRUE),
    max_vol = max(volume_ml, na.rm = TRUE),
    min_haul_factor = min(haul_factor, na.rm = TRUE),
    max_haul_factor = max(haul_factor, na.rm = TRUE),
    min_conc_10m2 = min(conc_10m2, na.rm = TRUE),
    max_conc_10m2 = max(conc_10m2, na.rm = TRUE),
    min_zoocount = min(zooplankton_count, na.rm = TRUE),
    max_zoocount = max(zooplankton_count, na.rm = TRUE),
    min_totcnt = min(totcnt, na.rm = TRUE),
    max_totcnt = max(totcnt, na.rm = TRUE)
  ) %>%
  pivot_longer(everything(), names_to = "Statistic", values_to = "Value") %>%
  print(n = Inf)

#################################################
# QA/QC checks
qa_qc_checks <- function(df, df_name) {
  cat("\n===== QA/QC Report for", df_name, "=====\n")
  
  # 1. check column classes
  cat("\nColumn Classes:\n")
  print(sapply(df, class))
  
  # 2. check for missing values
  cat("\nMissing Values per Column:\n")
  print(colSums(is.na(df)))
  
  # 3. summary statistics for numeric columns
  cat("\nSummary Statistics for Numeric Columns:\n")
  numeric_columns <- sapply(df, is.numeric)
  if (any(numeric_columns)) {
    print(summary(df[, numeric_columns]))
  } else {
    cat("No numeric columns to summarize.\n")
  }
  
  # 4. check for duplicates 
  cat("\nDuplicate Rows:\n")
  duplicates <- df[duplicated(df), ]
  if (nrow(duplicates) > 0) {
    cat("Found", nrow(duplicates), "duplicate rows:\n")
    print(duplicates)
  } else {
    cat("No duplicate rows found.\n")
  }
  
  # 5. unique values in factor columns 
  cat("\nUnique Values in Factor Columns:\n")
  factor_columns <- sapply(df, is.factor)
  if (any(factor_columns)) {
    unique_factors <- sapply(df[, factor_columns], unique)
    print(unique_factors)
  } else {
    cat("No factor columns to analyze.\n")
  }
  
  # 6. outlier (z-score)
  cat("\nOutliers (Z-scores > 3 or < -3) in Numeric Columns:\n")
  if (any(numeric_columns)) {
    z_scores <- scale(df[, numeric_columns])
    outliers <- abs(z_scores) > 3
    if (any(outliers)) {
      outlier_indices <- which(outliers, arr.ind = TRUE)
      cat("Outliers found:\n")
      print(outlier_indices)
    } else {
      cat("No outliers found.\n")
    }
  } else {
    cat("No numeric columns for outlier detection.\n")
  }
  
  cat("\n==============================\n")
}
# file path to save the output
output_file <- "qa_qc_report.txt"

# open connection to the file
sink(output_file)

# run QA/QC checks for each data frame
for (i in seq_along(data_frames)) {
  qa_qc_checks(data_frames[[i]], df_names[i])
}

# close connection
sink()

cat("QA/QC report saved to", output_file)

## ------------------------------------------ ##
#            Outliers -----
## ------------------------------------------ ##

exclude_columns <- c("sample_split_factor", "zoo_aliquot", "cruise", "station", 
                     "cast", "datetime_utc", "datetime_local", "day_night", "Season")

# loop over each data frame
for (i in seq_along(data_frames)) {
  df <- data_frames[[i]]
  df_name <- df_names[i]
  
  # identify numeric columns, excluding irrelevant ones
  numeric_columns <- setdiff(names(df)[sapply(df, is.numeric)], exclude_columns)
  
  # if there are numeric columns, proceed with outlier detection
  if (length(numeric_columns) > 0) {
    # calculate z-scores for numeric columns
    z_scores <- scale(df[, numeric_columns, drop = FALSE])
    
    # identify outliers (absolute z-score greater than 3)
    outliers <- abs(z_scores) > 3
    
    # if outliers exist, print
    if (any(outliers)) {
      cat("\nOutliers found in dataframe:", df_name, "\n")
      
      # extract row indices where outliers are present
      outlier_rows <- which(outliers, arr.ind = TRUE)
      
      # loop through each outlier to display its relevant details
      for (outlier in 1:nrow(outlier_rows)) {
        row_index <- outlier_rows[outlier, 1]
        col_index <- outlier_rows[outlier, 2]
        
        # extract row information
        outlier_value <- df[row_index, col_index]
        cruise <- df[row_index, "cruise"]
        station <- df[row_index, "station"]
        cast <- df[row_index, "cast"]
        taxa <- colnames(df)[col_index]  # get column name with the outlier
        
        cat("Outlier value:", outlier_value, "\n")
        cat("Cruise:", cruise, "\n")
        cat("Station:", station, "\n")
        cat("Cast:", cast, "\n")
        cat("Column:", taxa, "\n\n")  
      }
    } else {
      cat("No outliers found in dataframe:", df_name, "\n")
    }
  } else {
    cat("No numeric columns for outlier detection in dataframe:", df_name, "\n")
  }
}


## ------------------------------------------ ##
#            Export -----
## ------------------------------------------ ##

# loop through each data frame and write it to a separate CSV
for (i in 1:length(data_frames)) {
  write.csv(data_frames[[i]], file = paste0("output/",df_names[i], ".csv"), row.names = FALSE)
}


