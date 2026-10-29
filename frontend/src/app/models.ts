export interface EventItem { idEvent:number; description:string; dateDebut:string; dateFin:string; cout:number; }
export type Tache='INVITE'|'ORGANISATEUR'|'SERVEUR'|'ANIMATEUR';
export interface Participant { idPart?:number;nom:string;prenom:string;tache:Tache;events?:EventItem[]; }
export interface Logistics { idLog?:number;description:string;reserve:boolean;prixUnit:number;quantite:number; }
