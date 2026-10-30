import { Routes } from '@angular/router';
import { DashboardComponent } from './features/dashboard.component';
import { EventDetailComponent } from './features/event-detail.component';
import { EventsListComponent } from './features/events-list.component';

export const routes: Routes = [
  { path: 'dashboard', component: DashboardComponent, title: 'Dashboard · Events' },
  { path: 'events', component: EventsListComponent, title: 'Events · Events' },
  { path: 'events/:id', component: EventDetailComponent, title: 'Event details · Events' },
  { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
  { path: '**', redirectTo: 'dashboard' }
];
