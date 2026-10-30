import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticsService } from '../../core/services/logistics';
import { Logistics as LogisticsModel } from '../../models/logistics.model';

@Component({
  selector: 'app-logistics',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './logistics.html',
  styleUrl: './logistics.scss'
})
export class Logistics implements OnInit {
  private service = inject(LogisticsService);

  logistics: LogisticsModel[] = [];
  filteredLogistics: LogisticsModel[] = [];

  form: LogisticsModel = this.emptyForm();

  editing = false;
  showForm = false;
  reservedOnly = false;
  loading = false;

  message = '';
  error = '';
  totalCost: number | null = null;
  selectedId: number | null = null;

  ngOnInit(): void {
    this.loadLogistics();
  }

  emptyForm(): LogisticsModel {
    return {
      description: '',
      reserve: false,
      prixUnit: 0,
      quantite: 1
    };
  }

  loadLogistics(): void {
    this.loading = true;
    this.error = '';

    this.service.getAll().subscribe({
      next: (data) => {
        this.logistics = data;
        this.applyFilter();
        this.loading = false;
      },
      error: (err) => {
        this.error = 'Impossible de récupérer les logistiques. Vérifiez que le backend Spring Boot est démarré.';
        this.loading = false;
        console.error(err);
      }
    });
  }

  applyFilter(): void {
    this.filteredLogistics = this.reservedOnly
      ? this.logistics.filter(item => item.reserve)
      : [...this.logistics];
  }

  toggleFilter(): void {
    this.reservedOnly = !this.reservedOnly;
    this.applyFilter();
  }

  openAddForm(): void {
    this.form = this.emptyForm();
    this.editing = false;
    this.showForm = true;
    this.message = '';
    this.error = '';
  }

  openEditForm(item: LogisticsModel): void {
    this.form = { ...item };
    this.editing = true;
    this.showForm = true;
    this.message = '';
    this.error = '';
  }

  closeForm(): void {
    this.showForm = false;
    this.form = this.emptyForm();
  }

  save(): void {
    if (!this.form.description.trim() || this.form.quantite <= 0 || this.form.prixUnit < 0) {
      this.error = 'Veuillez vérifier les informations du formulaire.';
      return;
    }

    const request = this.editing
      ? this.service.update(this.form)
      : this.service.add(this.form);

    request.subscribe({
      next: () => {
        this.message = this.editing
          ? 'Logistique modifiée avec succès.'
          : 'Logistique ajoutée avec succès.';
        this.closeForm();
        this.loadLogistics();
      },
      error: (err) => {
        this.error = 'Une erreur est survenue lors de l’enregistrement.';
        console.error(err);
      }
    });
  }

  deleteItem(id?: number): void {
    if (id === undefined) return;

    if (!confirm('Voulez-vous vraiment supprimer cette logistique ?')) return;

    this.service.delete(id).subscribe({
      next: () => {
        this.message = 'Logistique supprimée avec succès.';
        this.loadLogistics();
      },
      error: (err) => {
        this.error = 'Erreur lors de la suppression.';
        console.error(err);
      }
    });
  }

  calculateCost(id?: number): void {
    if (id === undefined) return;

    this.selectedId = id;
    this.totalCost = null;

    this.service.getTotalCost(id).subscribe({
      next: (cost) => {
        this.totalCost = cost;
      },
      error: (err) => {
        this.error = 'Impossible de calculer le coût total.';
        console.error(err);
      }
    });
  }

  get totalItems(): number {
    return this.logistics.length;
  }

  get reservedItems(): number {
    return this.logistics.filter(item => item.reserve).length;
  }

  get totalQuantity(): number {
    return this.logistics.reduce((sum, item) => sum + item.quantite, 0);
  }

  get estimatedTotal(): number {
    return this.logistics.reduce(
      (sum, item) => sum + item.prixUnit * item.quantite,
      0
    );
  }
}


