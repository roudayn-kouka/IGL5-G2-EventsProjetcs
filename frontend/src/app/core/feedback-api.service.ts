import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { API_BASE_URL } from './api-base-url';
import { Feedback, FeedbackAverage, FeedbackRequest } from './models';

@Injectable({ providedIn: 'root' })
export class FeedbackApiService {
  private readonly http = inject(HttpClient);
  private readonly base = inject(API_BASE_URL).replace(/\/$/, '');

  getForEvent(eventId: number): Observable<Feedback[]> {
    return this.http.get<Feedback[]>(`${this.base}/feedback/event/${eventId}`);
  }

  getAverage(eventId: number): Observable<FeedbackAverage> {
    return this.http.get<FeedbackAverage>(`${this.base}/feedback/event/${eventId}/moyenne`);
  }

  create(eventId: number, participantId: number, request: FeedbackRequest): Observable<Feedback> {
    return this.http.post<Feedback>(`${this.base}/feedback/${eventId}/${participantId}`, request);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/feedback/${id}`);
  }
}
