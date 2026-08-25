# iHabitTracker

iHabitTracker is an iOS reimagining of my earlier terminal-based habit tracker, redesigned for a mobile-first experience.

The terminal project is the functional reference for this app: [terminal-habit-tracker](https://github.com/mktahmasbi99/terminal-habit-tracker).

## Product direction

iHabitTracker is a private, local-first iPhone habit tracker built with Swift and SwiftUI. Its primary interaction is deliberately fast: open the app, see today's habits and current streaks, then change a habit's status with one tap.

The app will use a local SQLite database whose schema is kept compatible with the terminal app. This preserves a path for a future import/export workflow and, later, carefully designed synchronization. The initial release will not include accounts or cloud/NAS/Google Drive synchronization.

## Status rules

- Every habit is daily in the initial version.
- A habit has one of three daily statuses: `Pending`, `Done`, or `Missed`.
- `Pending` is the default and is represented by no saved status record in SQLite.
- Users can change or undo a status at any time, including for past dates.
- Past `Pending` habits are unresolved and appear in notifications; today and future dates do not.
- Midnight makes an unfinished habit overdue, but it can still be backfilled later.
- Current streaks count consecutive explicit `Done` days. A `Missed` day or historical `Pending` day breaks the streak.
- The main screen shows the current streak beside each habit. Detailed streak history lives in the statistics area.

## Reference feature set

The iOS app will preserve the terminal tracker's feature set and behavior, translated into an iPhone-native design:

- Daily habit creation from any selected date
- Calendar navigation and visual status markers
- One-tap per-day status changes
- Current, longest, and historical streak statistics
- Per-habit, per-day notes
- Habit rename, archive, resurrection, and deletion safeguards
- Challenges with an inclusive end date and progress
- Local SQLite persistence
- Automatic and on-demand SQLite backups, plus restore management
- Notifications for past dates that still have pending habits

## Deliberately deferred

- Weekday/custom schedules
- Measurements, intensity, and scoring (for example, negative beer counts or offline-hours scores)
- Multi-device sync through Google Drive, a NAS, or another service

Future synchronization must include a documented conflict-resolution strategy for simultaneous offline edits. This belongs in the project roadmap and a future GitHub issue/milestone—not release notes until there is an actual release.

## Development plan

1. Define and test the SQLite compatibility layer against the terminal project's schema.
2. Build the SwiftUI Today screen: current-day habits, visible streaks, and one-tap state changes.
3. Add calendar navigation, unresolved-past-date notifications, and editable past days.
4. Add notes, statistics, archive/resurrection, challenges, and backup/restore flows.
5. Test on physical iPhones, then prepare TestFlight and App Store releases.

## License

This project is released under the [MIT License](LICENSE), consistent with the terminal-habit-tracker project.
