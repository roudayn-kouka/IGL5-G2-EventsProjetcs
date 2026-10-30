import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { DecimalPipe, DatePipe } from '@angular/common';
import { forkJoin } from 'rxjs';
import { EventsApiService } from '../core/events-api.service';
import { FeedbackApiService } from '../core/feedback-api.service';
import { ParticipantApiService } from '../core/participant-api.service';
import { apiErrorMessage } from '../core/api-error';
import {
  EventStats,
  Feedback,
  FeedbackAverage,
  Participant,
  TACHE_LABELS,
  Tache,
} from '../core/models';

const TACHE_COLORS: Record<string, string> = {
  INVITE: '#0ea5e9',
  ORGANISATEUR: '#8b5cf6',
  SERVEUR: '#f59e0b',
  ANIMATEUR: '#10b981',
};

@Component({
  selector: 'app-event-detail',
  standalone: true,
  imports: [RouterLink, FormsModule, DecimalPipe, DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="event-detail-page">
      <!-- Back -->
      <a routerLink="/events" class="back-link">← Back to events</a>

      <!-- Error -->
      @if (error()) {
        <div class="alert alert-error" role="alert">
          <span>⚠ {{ error() }}</span>
          <button class="btn-retry" (click)="load()">Retry</button>
        </div>
      }

      <!-- Loading -->
      @if (loading()) {
        <div class="loading-block">
          <div class="skeleton-header"></div>
          <div class="skeleton-grid">
            @for (_ of [1,2,3,4]; track $index) {
              <div class="skeleton-card"></div>
            }
          </div>
          <div class="skeleton-section"></div>
        </div>
      }

      <!-- Content -->
      @if (!loading() && event()) {
        <!-- Hero -->
        <div class="event-hero">
          <div class="hero-left">
            <div class="hero-eyebrow">Event #{{ event()!.idEvent }}</div>
            <h1 class="hero-title">{{ event()!.description }}</h1>
            <div class="hero-dates">
              <span class="hero-date-item">
                📅 <strong>{{ event()!.dateDebut }}</strong> – <strong>{{ event()!.dateFin }}</strong>
              </span>
              <span class="duration-pill">{{ event()!.dureeJours }} day{{ event()!.dureeJours !== 1 ? 's' : '' }}</span>
              @if (isUpcoming()) {
                <span class="status-pill status-upcoming">Upcoming</span>
              } @else {
                <span class="status-pill status-past">Past</span>
              }
            </div>
          </div>
          @if (average()) {
            <div class="rating-hero">
              <div class="rating-stars">{{ starString(average()!.averageRating) }}</div>
              <div class="rating-value">{{ average()!.averageRating | number:'1.1-1' }}</div>
              <div class="rating-count">{{ average()!.totalFeedbacks }} review{{ average()!.totalFeedbacks !== 1 ? 's' : '' }}</div>
            </div>
          }
        </div>

        <!-- Stats row -->
        <div class="stats-row">
          <div class="stat-card">
            <div class="stat-icon">👥</div>
            <div class="stat-value">{{ event()!.nbParticipants }}</div>
            <div class="stat-label">Participants</div>
          </div>
          <div class="stat-card">
            <div class="stat-icon">📦</div>
            <div class="stat-value">{{ event()!.nbLogisticsReservees }}<span class="stat-denom">/{{ event()!.nbLogistics }}</span></div>
            <div class="stat-label">Reserved</div>
          </div>
          <div class="stat-card">
            <div class="stat-icon">💶</div>
            <div class="stat-value">{{ event()!.coutLogistiqueReservee | number:'1.0-0' }}</div>
            <div class="stat-label">Cost (DT)</div>
          </div>
          <div class="stat-card">
            <div class="stat-icon">⭐</div>
            @if (event()!.averageRating > 0) {
              <div class="stat-value">{{ event()!.averageRating | number:'1.1-1' }}</div>
            } @else {
              <div class="stat-value stat-none">—</div>
            }
            <div class="stat-label">Avg Rating</div>
          </div>
        </div>

        <!-- Participants by task -->
        @if (taskBreakdown().length > 0) {
          <div class="section-card">
            <h2 class="section-title">Participants by Role</h2>
            <div class="task-chips">
              @for (item of taskBreakdown(); track item.label) {
                <div class="task-chip" [style.--chip-color]="item.color">
                  <span class="task-chip-count">{{ item.count }}</span>
                  <span class="task-chip-label">{{ item.label }}</span>
                </div>
              }
            </div>
          </div>
        }

        <!-- Feedback Section -->
        <div class="section-card">
          <div class="feedback-header">
            <h2 class="section-title">Feedback</h2>
            @if (average() && average()!.totalFeedbacks > 0) {
              <span class="feedback-count-badge">{{ average()!.totalFeedbacks }} review{{ average()!.totalFeedbacks !== 1 ? 's' : '' }}</span>
            }
          </div>

          @if (feedbackError()) {
            <div class="alert alert-error">⚠ {{ feedbackError() }}</div>
          }

          <!-- Feedback list -->
          @if (feedbacks().length > 0) {
            <div class="feedback-list">
              @for (fb of feedbacks(); track fb.id) {
                <div class="feedback-item">
                  <div class="fb-header">
                    <div class="fb-stars">{{ starString(fb.note) }}</div>
                    <span class="fb-note">{{ fb.note }}/5</span>
                    <span class="fb-participant">Participant #{{ fb.participantId }}</span>
                    <span class="fb-date">{{ fb.date | date:'dd MMM yyyy' }}</span>
                    <button
                      class="fb-delete"
                      (click)="deleteFeedback(fb.id)"
                      aria-label="Delete feedback"
                      title="Delete this feedback"
                    >🗑</button>
                  </div>
                  @if (fb.commentaire) {
                    <p class="fb-comment">"{{ fb.commentaire }}"</p>
                  }
                </div>
              }
            </div>
          } @else if (!feedbackLoading()) {
            <div class="feedback-empty">💬 No feedback yet for this event.</div>
          }

          @if (feedbackLoading()) {
            <div class="feedback-skeleton"></div>
          }
        </div>

        <!-- Submit Feedback -->
        <div class="section-card">
          <h2 class="section-title">Submit Feedback</h2>

          @if (submitSuccess()) {
            <div class="alert alert-success" role="status">
              ✅ Feedback submitted successfully!
              <button class="btn-dismiss" (click)="dismissSuccess()">✕</button>
            </div>
          }

          @if (submitError()) {
            <div class="alert alert-error" role="alert">
              ⚠ {{ submitError() }}
              <button class="btn-dismiss" (click)="dismissError()">✕</button>
            </div>
          }

          <form class="feedback-form" (ngSubmit)="submitFeedback()" #feedbackForm="ngForm">
            <!-- Participant selection -->
            <div class="form-row">
              <label class="form-label" for="participant-select">Participant</label>
              @if (participantsLoading()) {
                <div class="select-skeleton"></div>
              } @else if (participants().length > 0) {
                <select
                  id="participant-select"
                  class="form-select"
                  [(ngModel)]="selectedParticipantId"
                  name="participantId"
                  required
                >
                  <option [ngValue]="null" disabled>— Select a participant —</option>
                  @for (p of participants(); track p.idPart) {
                    <option [ngValue]="p.idPart">
                      #{{ p.idPart }} · {{ p.prenom }} {{ p.nom }} ({{ tacheLabel(p.tache) }})
                    </option>
                  }
                </select>
              } @else {
                <div class="participants-empty">
                  No participants found. Add participants first.
                </div>
              }
            </div>

            <!-- Star rating -->
            <div class="form-row">
              <label class="form-label">Rating</label>
              <div class="star-picker" role="radiogroup" aria-label="Rating">
                @for (star of [1,2,3,4,5]; track star) {
                  <button
                    type="button"
                    class="star-btn"
                    [class.active]="formNote >= star"
                    (click)="formNote = star"
                    (mouseenter)="hoverNote = star"
                    (mouseleave)="hoverNote = 0"
                    [attr.aria-label]="'Rate ' + star + ' out of 5'"
                  >{{ (hoverNote || formNote) >= star ? '★' : '☆' }}</button>
                }
                @if (formNote > 0) {
                  <span class="star-label">{{ formNote }}/5</span>
                }
              </div>
            </div>

            <!-- Comment -->
            <div class="form-row">
              <label class="form-label" for="comment-input">Comment <span class="optional">(optional)</span></label>
              <textarea
                id="comment-input"
                class="form-textarea"
                [(ngModel)]="formComment"
                name="commentaire"
                placeholder="Share your experience…"
                rows="3"
                maxlength="500"
              ></textarea>
              <div class="char-count">{{ formComment.length }}/500</div>
            </div>

            <div class="form-actions">
              <button
                type="submit"
                class="btn-submit"
                [disabled]="submitting() || formNote === 0 || selectedParticipantId === null"
              >
                @if (submitting()) {
                  <span class="spinner"></span> Submitting…
                } @else {
                  Submit Feedback
                }
              </button>
            </div>
          </form>
        </div>
      }
    </div>
  `,
  styles: [`
    .event-detail-page { display: flex; flex-direction: column; gap: 24px; }

    .back-link { display: inline-flex; align-items: center; color: #0ea5e9; text-decoration: none; font-weight: 600; font-size: .9rem; margin-bottom: 4px; }
    .back-link:hover { text-decoration: underline; }

    /* Alerts */
    .alert { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 18px; border-radius: 12px; font-size: .9rem; }
    .alert-error   { background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; }
    .alert-success { background: #f0fdf4; border: 1px solid #bbf7d0; color: #15803d; }
    .btn-retry, .btn-dismiss { background: none; border: none; cursor: pointer; font-size: .95rem; margin-left: auto; font-weight: 600; }
    .btn-retry { color: #dc2626; }
    .btn-dismiss { color: inherit; opacity: .6; }

    /* Loading skeletons */
    .loading-block { display: flex; flex-direction: column; gap: 20px; }
    .skeleton-header  { height: 120px; border-radius: 20px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
    .skeleton-grid  { display: grid; grid-template-columns: repeat(4,1fr); gap: 16px; }
    .skeleton-card  { height: 90px; border-radius: 16px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
    .skeleton-section { height: 200px; border-radius: 20px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
    @keyframes shimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} }

    /* Hero */
    .event-hero {
      background: linear-gradient(135deg, #0f172a 0%, #1e3a5f 100%);
      border-radius: 24px; padding: 32px 36px; display: flex; justify-content: space-between; align-items: flex-start; gap: 24px; flex-wrap: wrap;
    }
    .hero-left { flex: 1; }
    .hero-eyebrow { font-size: .78rem; font-weight: 700; color: #7dd3fc; text-transform: uppercase; letter-spacing: .08em; margin-bottom: 8px; }
    .hero-title { font-size: 1.9rem; font-weight: 800; color: #fff; margin: 0 0 16px; line-height: 1.25; }
    .hero-dates { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
    .hero-date-item { font-size: .9rem; color: #bfdbfe; }
    .duration-pill { background: rgba(255,255,255,.12); color: #e0f2fe; font-size: .76rem; font-weight: 700; padding: 3px 10px; border-radius: 999px; }
    .status-pill { font-size: .73rem; font-weight: 700; padding: 3px 10px; border-radius: 999px; text-transform: uppercase; }
    .status-upcoming { background: #d1fae5; color: #065f46; }
    .status-past     { background: #f1f5f9; color: #64748b; }

    .rating-hero { text-align: center; color: #fff; flex-shrink: 0; }
    .rating-stars { font-size: 1.6rem; letter-spacing: 2px; color: #fbbf24; }
    .rating-value { font-size: 2.4rem; font-weight: 900; margin-top: 4px; }
    .rating-count { font-size: .8rem; color: #bfdbfe; margin-top: 4px; }

    /* Stats row */
    .stats-row { display: grid; grid-template-columns: repeat(4,1fr); gap: 16px; }
    .stat-card { background: #fff; border-radius: 16px; padding: 20px; text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,.06); transition: transform .2s, box-shadow .2s; }
    .stat-card:hover { transform: translateY(-3px); box-shadow: 0 6px 20px rgba(0,0,0,.08); }
    .stat-icon { font-size: 1.5rem; margin-bottom: 8px; }
    .stat-value { font-size: 1.7rem; font-weight: 800; color: #0f172a; }
    .stat-denom { font-size: 1rem; font-weight: 500; color: #94a3b8; }
    .stat-none { color: #cbd5e1; }
    .stat-label { font-size: .72rem; font-weight: 700; color: #94a3b8; text-transform: uppercase; letter-spacing: .05em; margin-top: 4px; }

    /* Section card */
    .section-card { background: #fff; border-radius: 20px; padding: 24px 28px; box-shadow: 0 1px 3px rgba(0,0,0,.06); display: flex; flex-direction: column; gap: 16px; }
    .section-title { font-size: 1.1rem; font-weight: 700; color: #0f172a; margin: 0; }

    /* Task chips */
    .task-chips { display: flex; flex-wrap: wrap; gap: 12px; }
    .task-chip {
      display: flex; align-items: center; gap: 8px; padding: 10px 16px; border-radius: 12px;
      background: color-mix(in srgb, var(--chip-color) 12%, #fff); border: 1.5px solid color-mix(in srgb, var(--chip-color) 25%, #fff);
    }
    .task-chip-count { font-size: 1.2rem; font-weight: 800; color: var(--chip-color); }
    .task-chip-label { font-size: .85rem; font-weight: 600; color: #374151; }

    /* Feedback section */
    .feedback-header { display: flex; align-items: center; gap: 12px; }
    .feedback-count-badge { background: #f1f5f9; color: #64748b; font-size: .78rem; font-weight: 700; padding: 3px 10px; border-radius: 999px; }

    .feedback-list { display: flex; flex-direction: column; gap: 14px; }
    .feedback-item { background: #f8fafc; border-radius: 14px; padding: 16px 18px; border: 1px solid #f1f5f9; }
    .fb-header { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
    .fb-stars { color: #fbbf24; font-size: 1rem; letter-spacing: 1px; }
    .fb-note { font-size: .85rem; font-weight: 700; color: #374151; }
    .fb-participant { font-size: .8rem; color: #64748b; background: #f1f5f9; padding: 2px 8px; border-radius: 6px; }
    .fb-date { font-size: .78rem; color: #94a3b8; margin-left: auto; }
    .fb-delete { background: none; border: none; cursor: pointer; font-size: 1rem; color: #f87171; padding: 2px 4px; border-radius: 6px; transition: background .2s; }
    .fb-delete:hover { background: #fef2f2; }
    .fb-comment { margin: 10px 0 0; font-size: .88rem; color: #374151; font-style: italic; line-height: 1.5; }
    .feedback-empty { color: #94a3b8; font-size: .9rem; padding: 12px 0; }
    .feedback-skeleton { height: 80px; border-radius: 14px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }

    /* Feedback form */
    .feedback-form { display: flex; flex-direction: column; gap: 20px; }
    .form-row { display: flex; flex-direction: column; gap: 6px; }
    .form-label { font-size: .86rem; font-weight: 700; color: #374151; }
    .optional { font-weight: 400; color: #94a3b8; }

    .form-select {
      padding: 10px 14px; border: 1.5px solid #e2e8f0; border-radius: 12px; font-size: .92rem;
      background: #fff; color: #0f172a; outline: none; cursor: pointer;
      transition: border-color .2s, box-shadow .2s;
    }
    .form-select:focus { border-color: #0ea5e9; box-shadow: 0 0 0 3px rgba(14,165,233,.12); }

    .select-skeleton { height: 44px; border-radius: 12px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }

    .participants-empty { font-size: .85rem; color: #94a3b8; padding: 10px 0; }

    .star-picker { display: flex; align-items: center; gap: 4px; }
    .star-btn { background: none; border: none; font-size: 2rem; cursor: pointer; color: #d1d5db; transition: color .1s, transform .1s; padding: 0 2px; line-height: 1; }
    .star-btn.active, .star-btn:hover { color: #fbbf24; transform: scale(1.15); }
    .star-label { font-size: .9rem; font-weight: 700; color: #64748b; margin-left: 8px; }

    .form-textarea {
      padding: 10px 14px; border: 1.5px solid #e2e8f0; border-radius: 12px; font-size: .92rem;
      background: #fff; color: #0f172a; outline: none; resize: vertical; line-height: 1.5;
      transition: border-color .2s, box-shadow .2s;
    }
    .form-textarea:focus { border-color: #0ea5e9; box-shadow: 0 0 0 3px rgba(14,165,233,.12); }
    .char-count { text-align: right; font-size: .75rem; color: #94a3b8; }

    .form-actions { display: flex; justify-content: flex-end; }
    .btn-submit {
      background: linear-gradient(135deg, #0ea5e9, #0284c7); color: #fff; border: none; border-radius: 12px;
      padding: 12px 28px; font-size: .92rem; font-weight: 700; cursor: pointer;
      display: flex; align-items: center; gap: 8px; transition: opacity .2s, transform .15s;
    }
    .btn-submit:hover:not(:disabled) { transform: translateY(-1px); opacity: .92; }
    .btn-submit:disabled { opacity: .45; cursor: not-allowed; transform: none; }
    .spinner { width: 14px; height: 14px; border: 2px solid rgba(255,255,255,.35); border-top-color: #fff; border-radius: 50%; animation: spin .7s linear infinite; }
    @keyframes spin { to{ transform: rotate(360deg) } }

    @media (max-width: 720px) {
      .stats-row { grid-template-columns: repeat(2,1fr); }
      .skeleton-grid { grid-template-columns: repeat(2,1fr); }
      .event-hero { padding: 24px; }
      .hero-title { font-size: 1.4rem; }
    }
    @media (max-width: 480px) {
      .stats-row { grid-template-columns: repeat(2,1fr); }
      .section-card { padding: 18px; }
    }
  `],
})
export class EventDetailComponent implements OnInit {
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly event = signal<EventStats | null>(null);
  readonly feedbacks = signal<Feedback[]>([]);
  readonly average = signal<FeedbackAverage | null>(null);
  readonly feedbackLoading = signal(false);
  readonly feedbackError = signal<string | null>(null);
  readonly participants = signal<Participant[]>([]);
  readonly participantsLoading = signal(false);
  readonly submitting = signal(false);
  readonly submitSuccess = signal(false);
  readonly submitError = signal<string | null>(null);
  readonly taskBreakdown = signal<{ label: string; count: number; color: string }[]>([]);

  selectedParticipantId: number | null = null;
  formNote = 0;
  hoverNote = 0;
  formComment = '';

  private eventId = 0;

  private readonly route = inject(ActivatedRoute);
  private readonly eventsApi = inject(EventsApiService);
  private readonly feedbackApi = inject(FeedbackApiService);
  private readonly participantApi = inject(ParticipantApiService);

  ngOnInit(): void {
    this.eventId = Number(this.route.snapshot.paramMap.get('id'));
    this.load();
    this.loadParticipants();
  }

  load(): void {
    this.loading.set(true);
    this.error.set(null);
    forkJoin({
      event: this.eventsApi.getEvent(this.eventId),
      feedbacks: this.feedbackApi.getForEvent(this.eventId),
      average: this.feedbackApi.getAverage(this.eventId),
    }).subscribe({
      next: ({ event, feedbacks, average }) => {
        this.event.set(event);
        this.feedbacks.set(feedbacks);
        this.average.set(average);
        this.buildTaskBreakdown(event);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        this.error.set(apiErrorMessage(err, 'Failed to load event details.'));
        this.loading.set(false);
      },
    });
  }

  private loadParticipants(): void {
    this.participantsLoading.set(true);
    this.participantApi.getAll().subscribe({
      next: ps => {
        this.participants.set(ps);
        this.participantsLoading.set(false);
      },
      error: () => {
        this.participantsLoading.set(false);
      },
    });
  }

  submitFeedback(): void {
    if (this.formNote === 0 || this.selectedParticipantId === null) return;
    this.submitting.set(true);
    this.submitError.set(null);
    this.submitSuccess.set(false);

    this.feedbackApi
      .create(this.eventId, this.selectedParticipantId, {
        note: this.formNote,
        commentaire: this.formComment.trim() || undefined,
      })
      .subscribe({
        next: fb => {
          this.feedbacks.update(list => [fb, ...list]);
          this.formNote = 0;
          this.hoverNote = 0;
          this.formComment = '';
          this.selectedParticipantId = null;
          this.submitSuccess.set(true);
          this.submitting.set(false);
          // Refresh average
          this.feedbackApi.getAverage(this.eventId).subscribe(avg => this.average.set(avg));
        },
        error: (err: unknown) => {
          this.submitError.set(apiErrorMessage(err, 'Failed to submit feedback.'));
          this.submitting.set(false);
        },
      });
  }

  deleteFeedback(id: number): void {
    if (!confirm('Delete this feedback?')) return;
    this.feedbackApi.delete(id).subscribe({
      next: () => {
        this.feedbacks.update(list => list.filter(f => f.id !== id));
        this.feedbackApi.getAverage(this.eventId).subscribe(avg => this.average.set(avg));
      },
      error: (err: unknown) => {
        this.feedbackError.set(apiErrorMessage(err, 'Failed to delete feedback.'));
      },
    });
  }

  dismissSuccess(): void { this.submitSuccess.set(false); }
  dismissError(): void { this.submitError.set(null); }

  isUpcoming(): boolean {
    const ev = this.event();
    if (!ev) return false;
    return ev.dateFin >= new Date().toISOString().slice(0, 10);
  }

  starString(rating: number): string {
    const full = Math.round(rating);
    return '★'.repeat(Math.max(0, full)) + '☆'.repeat(Math.max(0, 5 - full));
  }

  tacheLabel(t: string): string {
    return TACHE_LABELS[t as Tache] ?? t;
  }

  private buildTaskBreakdown(ev: EventStats): void {
    const tasks = ev.participantsParTache ?? {};
    const items = (Object.entries(tasks) as [string, number][]).map(([key, count]) => ({
      label: TACHE_LABELS[key as Tache] ?? key,
      count: count ?? 0,
      color: TACHE_COLORS[key] ?? '#94a3b8',
    }));
    this.taskBreakdown.set(items);
  }
}
