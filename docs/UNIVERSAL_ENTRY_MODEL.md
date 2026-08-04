# Universal entry model

Asitra treats every user-created or imported record as an entry object. A list,
timeline, money report, tracker, trip, or calendar is a view of those objects—not
another place where the user must enter the same fact.

## Base lifecycle

Every entry has:

- a stable identifier;
- a title and optional note or attachment;
- a type and source;
- a start timestamp and optional end timestamp;
- edit and delete behavior;
- optional links to a list, trip, tracker, reminder, or calendar event.

Every entry can represent either a moment or a time block. External calendar or
reminder identifiers belong to the entry so updates and deletions can propagate
without creating duplicates.

## Type capabilities

| Type | Additional behavior |
| --- | --- |
| Task, reminder, routine | Complete, reopen, postpone, list projection |
| Expense | Amount, account, merchant category, trip link, money projections |
| Income, saving, investment | Amount, allocation and cash-flow projections |
| Asset or liability snapshot | Balance category and net-worth projection |
| Work, movement, sleep, screen time | Duration and source integration |
| Book or movie | Planned, in-progress, completed status |
| Food | Meal and nutrition metadata when available |
| Mood, journal, idea, note | Reflection, tags, photos, voice and AI context |

Capabilities are additive. The common lifecycle remains the same, while the
editor shows only the fields that apply to the selected type.

## Projection rule

An entry is the source of truth. Derived views must never own a second editable
copy of the same fact. A mutation follows this flow:

1. Validate the entry and its type-specific fields.
2. Save the canonical entry once.
3. Recalculate list, money, trip, tracker and Today projections.
4. Synchronize linked Apple or Google calendar/reminder records.
5. Sync the same entry revision to the user's cloud account.

The current compatibility layer keeps existing saved data readable while new
and edited records progressively gain the universal entry fields.
