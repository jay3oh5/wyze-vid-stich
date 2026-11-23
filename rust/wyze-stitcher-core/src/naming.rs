use crate::models::OutputNamingFormat;

/// Formats a raw `YYYYMMDD` folder name into `YYYY-MM-DD`.
pub fn format_day_display(day: &str) -> String {
    if day.len() == 8 && day.chars().all(|c| c.is_ascii_digit()) {
        format!("{}-{}-{}", &day[0..4], &day[4..6], &day[6..8])
    } else {
        day.to_string()
    }
}

/// Formats the compiled output filename according to the user's Settings preference:
/// - `TwentyFourHour` (default): `2026-05-29_0000.mp4`, `2026-05-29_1400.mp4`
/// - `TwelveHourLegacy`: `2026-05-29_!12AM.mp4`, `2026-05-29_2PM.mp4`
pub fn format_output_filename(day: &str, hour: &str, format: OutputNamingFormat) -> String {
    let formatted_date = format_day_display(day);
    let parsed_hour = hour.parse::<u32>().unwrap_or(0).min(23);

    match format {
        OutputNamingFormat::TwentyFourHour => {
            format!("{formatted_date}_{parsed_hour:02}00.mp4")
        }
        OutputNamingFormat::TwelveHourLegacy => {
            let ampm = if parsed_hour >= 12 { "PM" } else { "AM" };
            let display_h = if parsed_hour % 12 == 0 {
                12
            } else {
                parsed_hour % 12
            };
            let hour_part = if display_h == 12 && ampm == "AM" {
                "!12AM".to_string()
            } else {
                format!("{display_h}{ampm}")
            };
            format!("{formatted_date}_{hour_part}.mp4")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_24_hour_sortable_names() {
        assert_eq!(
            format_output_filename("20260529", "00", OutputNamingFormat::TwentyFourHour),
            "2026-05-29_0000.mp4"
        );
        assert_eq!(
            format_output_filename("20260529", "13", OutputNamingFormat::TwentyFourHour),
            "2026-05-29_1300.mp4"
        );
    }

    #[test]
    fn formats_12_hour_legacy_names_with_midnight_prefix() {
        assert_eq!(
            format_output_filename("20260529", "00", OutputNamingFormat::TwelveHourLegacy),
            "2026-05-29_!12AM.mp4"
        );
        assert_eq!(
            format_output_filename("20260529", "12", OutputNamingFormat::TwelveHourLegacy),
            "2026-05-29_12PM.mp4"
        );
        assert_eq!(
            format_output_filename("20260529", "17", OutputNamingFormat::TwelveHourLegacy),
            "2026-05-29_5PM.mp4"
        );
    }
}
