import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { API_BASE_URL } from './api-base-url';
import { Participant, Tache } from './models';

@Injectable({ providedIn: 'root' })
export class ParticipantApiService {
  private readonly http = inject(HttpClient);
  private readonly base = inject(API_BASE_URL).replace(/\/$/, '');

  getAll(): Observable<Participant[]> {
    return this.http.get<Participant[]>(`${this.base}/participant/all`);
  }

  getById(id: number): Observable<Participant> {
    return this.http.get<Participant>(`${this.base}/participant/${id}`);
  }

  create(participant: Omit<Participant, 'idPart'>): Observable<Participant> {
    return this.http.post<Participant>(`${this.base}/participant/add`, participant);
  }

  update(id: number, participant: Partial<Participant>): Observable<Participant> {
    return this.http.put<Participant>(`${this.base}/participant/update/${id}`, participant);
  }

  changeTache(id: number, tache: Tache): Observable<Participant> {
    return this.http.put<Participant>(`${this.base}/participant/${id}/tache/${tache}`, null);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/participant/delete/${id}`);
  }
}
