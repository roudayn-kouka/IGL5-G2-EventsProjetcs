import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Participant, Logistics } from './models';
@Injectable({providedIn:'root'})
export class ApiService {
  private http=inject(HttpClient);
  // URLs relatives au contexte Spring Boot, y compris en développement via proxy Angular.
  private prefix='/events';
  events(){return this.http.get<any[]>(`${this.prefix}/event-stats`);}
  // La liste des événements utilise le DTO de statistiques exposé par Spring Boot.
  participants(){return this.http.get<Participant[]>(`${this.prefix}/participant/all`);}
  addParticipant(p:Participant){return this.http.post<Participant>(`${this.prefix}/participant/add`,p);}
  updateParticipant(p:Participant){return this.http.put<Participant>(`${this.prefix}/participant/update/${p.idPart}`,p);}
  deleteParticipant(id:number){return this.http.delete<void>(`${this.prefix}/participant/delete/${id}`);}
  logistics(){return this.http.get<Logistics[]>(`${this.prefix}/logistics`);}
  addLogistics(l:Logistics){return this.http.post<Logistics>(`${this.prefix}/logistics`,l);}
  updateLogistics(l:Logistics){return this.http.put<Logistics>(`${this.prefix}/logistics`,l);}
  deleteLogistics(id:number){return this.http.delete<void>(`${this.prefix}/logistics/${id}`);}
}
