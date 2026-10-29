import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpErrorResponse } from '@angular/common/http';
import { ApiService } from './api.service';
import { Logistics, Participant, Tache } from './models';
type Page='events'|'participants'|'logistics';
@Component({selector:'app-root',standalone:true,imports:[CommonModule,FormsModule],templateUrl:'./app.component.html'})
export class AppComponent implements OnInit {
  private api=inject(ApiService);
  page:Page='events'; busy=false; error=''; success=''; query='';
  events:any[]=[]; participants:Participant[]=[]; logistics:Logistics[]=[];
  editingParticipant=false; editingLogistics=false;
  participant:Participant=this.emptyParticipant(); logistic:Logistics=this.emptyLogistic();
  readonly taches:Tache[]=['INVITE','ORGANISATEUR','SERVEUR','ANIMATEUR'];
  ngOnInit(){this.reload();}
  emptyParticipant():Participant{return {nom:'',prenom:'',tache:'INVITE'};}
  emptyLogistic():Logistics{return {description:'',reserve:false,prixUnit:0,quantite:1};}
  switchPage(p:Page){this.page=p;this.query='';this.error='';this.success='';this.reload();}
  reload(){this.busy=true;this.error='';
    if(this.page==='events')this.api.events().subscribe({next:r=>{this.events=r;this.busy=false},error:e=>this.fail(e)});
    if(this.page==='participants')this.api.participants().subscribe({next:r=>{this.participants=r;this.busy=false},error:e=>this.fail(e)});
    if(this.page==='logistics')this.api.logistics().subscribe({next:r=>{this.logistics=r;this.busy=false},error:e=>this.fail(e)});
  }
  fail(e:unknown){this.busy=false;this.error=e instanceof HttpErrorResponse?`Erreur HTTP ${e.status||'réseau'} : ${e.error?.message || e.message}`:'Une erreur est survenue.';}
  get filteredParticipants(){const q=this.query.toLocaleLowerCase();return this.participants.filter(p=>`${p.nom} ${p.prenom} ${p.tache}`.toLocaleLowerCase().includes(q));}
  get filteredLogistics(){const q=this.query.toLocaleLowerCase();return this.logistics.filter(l=>l.description.toLocaleLowerCase().includes(q));}
  get filteredEvents(){const q=this.query.toLocaleLowerCase();return this.events.filter(e=>JSON.stringify(e).toLocaleLowerCase().includes(q));}
  get reservedCount(){return this.logistics.filter(l=>l.reserve).length;}
  get logisticsTotal(){return this.logistics.reduce((s,l)=>s+l.prixUnit*l.quantite,0);}
  newParticipant(){this.participant=this.emptyParticipant();this.editingParticipant=true;this.error='';}
  editParticipant(p:Participant){this.participant={idPart:p.idPart,nom:p.nom,prenom:p.prenom,tache:p.tache};this.editingParticipant=true;this.error='';}
  saveParticipant(){if(!this.participant.nom.trim()||!this.participant.prenom.trim())return;
    this.busy=true;const op=this.participant.idPart?this.api.updateParticipant(this.participant):this.api.addParticipant(this.participant);
    op.subscribe({next:()=>{this.editingParticipant=false;this.success='Participant enregistré.';this.reload()},error:e=>this.fail(e)});
  }
  removeParticipant(p:Participant){if(p.idPart==null||!confirm(`Supprimer ${p.prenom} ${p.nom} ?`))return;
    this.api.deleteParticipant(p.idPart).subscribe({next:()=>{this.success='Participant supprimé.';this.reload()},error:e=>this.fail(e)});
  }
  newLogistic(){this.logistic=this.emptyLogistic();this.editingLogistics=true;this.error='';}
  editLogistic(l:Logistics){this.logistic={...l};this.editingLogistics=true;this.error='';}
  saveLogistic(){if(!this.logistic.description.trim()||this.logistic.prixUnit<0||this.logistic.quantite<1)return;
    this.busy=true;const op=this.logistic.idLog?this.api.updateLogistics(this.logistic):this.api.addLogistics(this.logistic);
    op.subscribe({next:()=>{this.editingLogistics=false;this.success='Logistique enregistrée.';this.reload()},error:e=>this.fail(e)});
  }
  removeLogistic(l:Logistics){if(l.idLog==null||!confirm(`Supprimer « ${l.description} » ?`))return;
    this.api.deleteLogistics(l.idLog).subscribe({next:()=>{this.success='Élément supprimé.';this.reload()},error:e=>this.fail(e)});
  }
  eventName(e:any):string{return e.description??e.nom??e.nomEvent??`Événement #${e.idEvent??'?'}`;}
  eventDate(e:any):string{return e.dateDebut??e.date??'';}
  money(n:number):string{return new Intl.NumberFormat('fr-FR',{style:'currency',currency:'TND'}).format(n||0);}
}
