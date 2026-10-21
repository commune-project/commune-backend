# forum-search Specification

## Purpose

Make readable discussions and communities discoverable through site-scoped search that supports Chinese text without exposing restricted results.

## Requirements

### Requirement: Access-filtered Chinese search
Search SHALL support literal case-insensitive substring matching of community name, title, and description and post title and textual body, including contiguous Chinese queries. User query punctuation SHALL NOT become wildcard or executable query syntax. Results SHALL include only communities scoped to the resolved site and posts received and currently visible there, using current read permissions and inclusion rules before pagination. Hidden, deleted, removed, rejected, blocked, and unreadable content SHALL NOT contribute result rows or counts. Search SHALL NOT fetch remote content.

#### Scenario: Chinese query and private newer matches
- **WHEN** a reader searches for a Chinese substring with inaccessible and visible matching posts
- **THEN** only visible matches appear and excluded rows do not consume the requested page

#### Scenario: SQL-like punctuation
- **WHEN** the query contains percent, underscore, quotes, or backslashes
- **THEN** these characters are searched literally without changing authorization or query structure

### Requirement: Bounded deterministic search responses
Search SHALL accept an explicit communities or posts kind, use the existing limit/offset defaults and maximum, reject missing or invalid kinds and queries with 400, and return `{items,limit,offset}` with empty arrays for exhausted pages. Community results SHALL sort by name then ID ascending; posts SHALL sort by authored time descending then ID ascending. Query length SHALL be bounded. Viewer-dependent responses SHALL be no-store, preserve applicable administrative-read auditing, and propagate storage failures as unavailable errors.

#### Scenario: Stable pagination and failure
- **WHEN** equal-time posts span pages or authorization storage is unavailable
- **THEN** pagination uses the stable ID tie-breaker, and storage failure returns an unavailable error rather than an empty success
