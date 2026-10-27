# Feedback (Phase 2)

The existing port (8089) and context path (`/events`) are unchanged.

| Method | Path relative to `/events` | Success | Errors |
| --- | --- | --- | --- |
| POST | `/feedback/{idEvent}/{idPart}` | 201, FeedbackResponse | 400 invalid rating, membership or completion; 404 missing event/participant; 409 duplicate |
| GET | `/feedback/event/{id}` | 200, FeedbackResponse array (possibly empty) | 404 missing event |
| GET | `/feedback/event/{id}/moyenne` | 200, `{eventId, averageRating, totalFeedbacks}` | 404 missing event |
| DELETE | `/feedback/{id}` | 204, empty body | 404 missing feedback |

Requests contain `note` (required JSON integer from 1 through 5) and optional
`commentaire` (text). Decimal values, strings, booleans, null and missing ratings
are rejected. Response DTOs expose only `id`, `note`, `commentaire`, `date`,
`eventId` and `participantId`; entity graphs are never serialized. Errors contain
`status`, `error` and `message`.

`FeedbackService` validates ratings even for non-HTTP callers, loads the existing
event and participant, and checks membership through the owning
`Participant.events` relationship. It generates the timestamp using its Clock.
`FeedbackRequest` additionally applies Bean Validation; its rating deserializer
prevents Jackson from truncating decimals.

## Completion and time

The existing event model stores an inclusive `LocalDate dateFin`, without a time
or completion status. Feedback is therefore allowed only when `dateFin` is
strictly before today's date. An event ending today, or without an end date,
cannot be reviewed. This agrees with the dashboard's inclusive end-date display.
Production uses the server's default time zone; fixed clocks with Africa/Tunis
verify the midnight boundary in tests. Feedback timestamps are UTC `Instant`s.
Precise intraday completion would require an agreed change to the event model.

## Persistence and conflicts

Feedback has mandatory lazy many-to-one event/participant references, a non-null
rating and server timestamp, and an optional LOB comment. Existing entities and
their mappings are unchanged. The named database constraint
`uk_feedback_event_participant` enforces uniqueness of `(event_id, participant_id)`.
The service checks duplicates first and flushes inserts inside the transaction;
violations of that named constraint (including concurrent submissions) become
409 responses. Unrelated integrity errors are not incorrectly labeled duplicates.
An event with no feedback has average `0.0` and count `0`.

No authentication system exists in this project. Deletion authorization remains
outside this assignment's scope; this endpoint follows the existing unauthenticated
API conventions.

## Tests and build

- `FeedbackServiceTest`: JUnit/Mockito rules, missing resources, averages, deletion,
  duplicate-key translation, unrelated integrity failures and local midnight.
- `FeedbackRepositoryTest`: real H2 mappings, membership, timestamps, averages,
  required columns, uniqueness and independent event/participant pairs.
- `FeedbackControllerIntegrationTest`: real Spring services/repositories/H2 and
  MockMvc, `/events` paths, validation, error codes, DTOs and the complete lifecycle.
- `FeedbackConcurrencyIntegrationTest`: simultaneous HTTP submissions in separate
  transactions, one 201 and one 409, committed reads with open-in-view disabled.

Run `mvn clean verify`. Focused checks are
`mvn -Dtest=FeedbackRepositoryTest test`,
`mvn -Dtest=FeedbackServiceTest,FeedbackRepositoryTest test` and
`mvn -Dtest=Feedback*Test test`. Tests use only H2, without an external MySQL server.
JaCoCo HTML is generated at `target/site/jacoco/index.html`.

## Manual PowerShell requests

Use IDs for an existing participant assigned to an event whose end date is past:

```powershell
$base = 'http://localhost:8089/events'
$eventId = 1
$participantId = 2
$created = Invoke-RestMethod -Method Post -Uri "$base/feedback/$eventId/$participantId" `
    -ContentType 'application/json' -Body '{"note":5,"commentaire":"Excellent event!"}'
Invoke-RestMethod "$base/feedback/event/$eventId"
Invoke-RestMethod "$base/feedback/event/$eventId/moyenne"
Invoke-RestMethod -Method Delete -Uri "$base/feedback/$($created.id)"
```
