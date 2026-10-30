// ─── Enums ────────────────────────────────────────────────────────────────────

export type Tache = 'INVITE' | 'ORGANISATEUR' | 'SERVEUR' | 'ANIMATEUR';

export const TACHE_LABELS: Record<Tache, string> = {
  INVITE: 'Invité',
  ORGANISATEUR: 'Organisateur',
  SERVEUR: 'Serveur',
  ANIMATEUR: 'Animateur',
};

// ─── Entities (raw backend payloads) ──────────────────────────────────────────

export interface Event {
  idEvent: number;
  description: string;
  dateDebut: string;      // ISO date: "yyyy-MM-dd"
  dateFin: string;        // ISO date: "yyyy-MM-dd"
  cout: number;
}

export interface Participant {
  idPart: number;
  nom: string;
  prenom: string;
  tache: Tache;
  events?: Event[];   // backend includes nested events on participant responses
}

export interface Logistics {
  idLog: number;
  description: string;
  reserve: boolean;
  prixUnit: number;
  quantite: number;
}

// ─── Stats DTOs ───────────────────────────────────────────────────────────────

export interface EventStats {
  idEvent: number;
  description: string;
  dateDebut: string;
  dateFin: string;
  dureeJours: number;
  nbParticipants: number;
  participantsParTache: Partial<Record<Tache, number>>;
  nbLogistics: number;
  nbLogisticsReservees: number;
  coutLogistiqueReservee: number;
  averageRating: number;
}

export interface GlobalStats {
  nbEvents: number;
  nbEventsAVenir: number;
  nbParticipants: number;
  nbLogistics: number;
  nbLogisticsReservees: number;
  tauxReservation: number;
  coutTotalLogistiqueReservee: number;
  participantsParTache: Partial<Record<Tache, number>>;
}

// ─── Feedback DTOs ────────────────────────────────────────────────────────────

export interface Feedback {
  id: number;
  note: number;
  commentaire: string | null;
  date: string;           // ISO instant / date string
  eventId: number;
  participantId: number;
}

export interface FeedbackAverage {
  eventId: number;
  averageRating: number;
  totalFeedbacks: number;
}

export interface FeedbackRequest {
  note: number;
  commentaire?: string;
}
