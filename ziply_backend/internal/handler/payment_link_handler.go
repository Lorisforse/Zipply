package handler

import (
	"errors"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// PaymentLinkHandler gestisce le richieste HTTP per i link di pagamento.
type PaymentLinkHandler struct {
	usecase *usecase.PaymentLinkUsecase
}

// NewPaymentLinkHandler crea un nuovo PaymentLinkHandler.
func NewPaymentLinkHandler(usecase *usecase.PaymentLinkUsecase) *PaymentLinkHandler {
	return &PaymentLinkHandler{usecase: usecase}
}

// WebPageData contiene i dati passati al template HTML della pagina di pagamento.
type WebPageData struct {
	ID             string
	RideID         string
	TotalAmount    float64
	Participants   int
	AmountPerHead  float64
	ValidUntil     string
	Status         string
	PrenotanteName string
	Error          string
	State          string // "pay", "success", "error"
}

// getBaseURL rileva dinamicamente il protocollo e l'host, supportando sia localhost che la produzione.
func getBaseURL(r *http.Request) string {
	if r.Host != "" && strings.Contains(r.Host, "api.lorisamato.it") {
		return "https://api.lorisamato.it/ziply/api"
	}
	scheme := "http"
	if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	return fmt.Sprintf("%s://%s", scheme, r.Host)
}

// Create gestisce POST /rides/{id}/payment-link
func (h *PaymentLinkHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	rideID := r.PathValue("id")
	if rideID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID corsa mancante"})
		return
	}

	pl, err := h.usecase.Generate(r.Context(), userID, rideID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa non trovata"})
		default:
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		return
	}

	// Costruiamo il link condivisibile nel formato web
	shareableLink := fmt.Sprintf("%s/payment-links/%s/pay-web", getBaseURL(r), pl.ID)

	response := map[string]any{
		"id":              pl.ID,
		"ride_id":         pl.RideID,
		"total_amount":    pl.TotalAmount,
		"participants":    pl.Participants,
		"amount_per_head": pl.AmountPerHead,
		"valid_until":     pl.ValidUntil.UTC().Format("2006-01-02T15:04:05Z"),
		"status":          pl.Status,
		"link":            shareableLink,
	}

	writeJSON(w, http.StatusCreated, response)
}

// Get gestisce GET /payment-links/{id}
func (h *PaymentLinkHandler) Get(w http.ResponseWriter, r *http.Request) {
	_, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	linkID := r.PathValue("id")
	if linkID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID link di pagamento mancante"})
		return
	}

	pl, err := h.usecase.Get(r.Context(), linkID)
	if err != nil {
		if errors.Is(err, domain.ErrPaymentLinkNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "link di pagamento non trovato"})
		} else {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore interno del server"})
		}
		return
	}

	response := map[string]any{
		"id":              pl.ID,
		"ride_id":         pl.RideID,
		"total_amount":    pl.TotalAmount,
		"participants":    pl.Participants,
		"amount_per_head": pl.AmountPerHead,
		"valid_until":     pl.ValidUntil.UTC().Format("2006-01-02T15:04:05Z"),
		"status":          pl.Status,
		"prenotante_name": pl.PrenotanteName,
	}

	writeJSON(w, http.StatusOK, response)
}

// Pay gestisce POST /payment-links/{id}/pay
func (h *PaymentLinkHandler) Pay(w http.ResponseWriter, r *http.Request) {
	_, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	linkID := r.PathValue("id")
	if linkID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID link di pagamento mancante"})
		return
	}

	err := h.usecase.Pay(r.Context(), linkID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrPaymentLinkNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "link di pagamento non trovato"})
		case errors.Is(err, domain.ErrPaymentLinkExpired):
			writeJSON(w, http.StatusGone, map[string]string{"error": "link scaduto"})
		case err.Error() == "quota già pagata":
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		default:
			log.Printf("[PAYMENT_LINKS] pay failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "paid",
		"message": "pagamento quota effettuato con successo",
	})
}

// GetCreditBalance gestisce GET /users/credit-balance
func (h *PaymentLinkHandler) GetCreditBalance(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	balance, err := h.usecase.GetUserCreditBalance(r.Context(), userID)
	if err != nil {
		if errors.Is(err, domain.ErrUserNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "utente non trovato"})
		} else {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"credit_balance": balance,
	})
}

// ShowPayWeb gestisce GET /payment-links/{id}/pay-web (PUBBLICO)
func (h *PaymentLinkHandler) ShowPayWeb(w http.ResponseWriter, r *http.Request) {
	linkID := r.PathValue("id")
	if linkID == "" {
		h.renderErrorPage(w, "ID link di pagamento mancante")
		return
	}

	pl, err := h.usecase.Get(r.Context(), linkID)
	if err != nil {
		if errors.Is(err, domain.ErrPaymentLinkNotFound) {
			h.renderErrorPage(w, "Link di pagamento non trovato")
		} else {
			h.renderErrorPage(w, "Errore interno del server")
		}
		return
	}

	// Se scaduto o pagato, reindirizza alle rispettive visualizzazioni
	if pl.Status == "expired" || time.Now().After(pl.ValidUntil) {
		h.renderErrorPage(w, "Questo link di pagamento è scaduto")
		return
	}

	if pl.Status == "paid" {
		h.renderSuccessPage(w, pl)
		return
	}

	data := WebPageData{
		ID:             pl.ID,
		RideID:         pl.RideID,
		TotalAmount:    pl.TotalAmount,
		Participants:   pl.Participants,
		AmountPerHead:  pl.AmountPerHead,
		ValidUntil:     pl.ValidUntil.Format("02/01/2006 15:04"),
		Status:         pl.Status,
		PrenotanteName: pl.PrenotanteName,
		State:          "pay",
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := webTemplate.Execute(w, data); err != nil {
		log.Printf("[PAY_WEB] template execution failed: %v", err)
	}
}

// ProcessPayWeb gestisce POST /payment-links/{id}/pay-web (PUBBLICO)
func (h *PaymentLinkHandler) ProcessPayWeb(w http.ResponseWriter, r *http.Request) {
	linkID := r.PathValue("id")
	if linkID == "" {
		h.renderErrorPage(w, "ID link di pagamento mancante")
		return
	}

	pl, err := h.usecase.Get(r.Context(), linkID)
	if err != nil {
		h.renderErrorPage(w, "Link di pagamento non trovato")
		return
	}

	err = h.usecase.Pay(r.Context(), linkID)
	if err != nil {
		if errors.Is(err, domain.ErrPaymentLinkExpired) {
			h.renderErrorPage(w, "Il link di pagamento è scaduto")
		} else if err.Error() == "quota già pagata" {
			h.renderSuccessPage(w, pl)
		} else {
			h.renderErrorPage(w, fmt.Sprintf("Impossibile elaborare il pagamento: %v", err))
		}
		return
	}

	// Recupera di nuovo il link per avere lo stato aggiornato
	pl, _ = h.usecase.Get(r.Context(), linkID)
	h.renderSuccessPage(w, pl)
}

func (h *PaymentLinkHandler) renderErrorPage(w http.ResponseWriter, errMsg string) {
	data := WebPageData{
		Error: errMsg,
		State: "error",
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_ = webTemplate.Execute(w, data)
}

func (h *PaymentLinkHandler) renderSuccessPage(w http.ResponseWriter, pl *domain.PaymentLink) {
	data := WebPageData{
		ID:             pl.ID,
		AmountPerHead:  pl.AmountPerHead,
		PrenotanteName: pl.PrenotanteName,
		State:          "success",
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_ = webTemplate.Execute(w, data)
}

var webTemplate = template.Must(template.New("web").Parse(`<!DOCTYPE html>
<html lang="it">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ziply - Pagamento Quota</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #1A1A1A;
            --surface-color: rgba(37, 37, 37, 0.85);
            --primary-color: #F69659;
            --primary-hover: #e0834c;
            --text-color: #FFFFFF;
            --text-muted: #A0A0A0;
            --border-color: rgba(255, 255, 255, 0.1);
            --error-color: #FF5A5F;
            --success-color: #4CAF50;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Outfit', sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            overflow-x: hidden;
            position: relative;
        }

        body::before {
            content: '';
            position: absolute;
            width: 300px;
            height: 300px;
            background: radial-gradient(circle, rgba(246, 150, 89, 0.15) 0%, rgba(0,0,0,0) 70%);
            top: -50px;
            right: -50px;
            z-index: 0;
        }

        body::after {
            content: '';
            position: absolute;
            width: 350px;
            height: 350px;
            background: radial-gradient(circle, rgba(246, 150, 89, 0.1) 0%, rgba(0,0,0,0) 70%);
            bottom: -80px;
            left: -80px;
            z-index: 0;
        }

        .container {
            width: 100%;
            max-width: 480px;
            padding: 24px;
            z-index: 10;
        }

        .card {
            background: var(--surface-color);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid var(--border-color);
            border-radius: 24px;
            padding: 40px 32px;
            box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37);
            text-align: center;
            animation: fadeIn 0.6s cubic-bezier(0.16, 1, 0.3, 1);
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .logo {
            font-size: 32px;
            font-weight: 700;
            color: var(--primary-color);
            margin-bottom: 24px;
            letter-spacing: 1px;
            display: inline-block;
            position: relative;
        }

        .logo::after {
            content: '';
            position: absolute;
            width: 8px;
            height: 8px;
            background: var(--text-color);
            border-radius: 50%;
            bottom: 8px;
            right: -10px;
        }

        .title {
            font-size: 22px;
            font-weight: 600;
            margin-bottom: 8px;
        }

        .subtitle {
            font-size: 14px;
            color: var(--text-muted);
            margin-bottom: 32px;
        }

        .summary-box {
            background: rgba(255, 255, 255, 0.03);
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            padding: 20px;
            margin-bottom: 32px;
            text-align: left;
        }

        .summary-row {
            display: flex;
            justify-content: space-between;
            margin-bottom: 12px;
            font-size: 15px;
        }

        .summary-row:last-child {
            margin-bottom: 0;
            border-top: 1px solid rgba(255, 255, 255, 0.08);
            padding-top: 12px;
            font-weight: 600;
        }

        .summary-label {
            color: var(--text-muted);
        }

        .amount-highlight {
            font-size: 20px;
            color: var(--primary-color);
        }

        .form-group {
            text-align: left;
            margin-bottom: 20px;
        }

        label {
            display: block;
            font-size: 13px;
            font-weight: 500;
            color: var(--text-muted);
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        input {
            width: 100%;
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 14px 16px;
            color: var(--text-color);
            font-family: inherit;
            font-size: 15px;
            transition: all 0.2s ease;
        }

        input:focus {
            outline: none;
            border-color: var(--primary-color);
            background: rgba(255, 255, 255, 0.08);
            box-shadow: 0 0 0 3px rgba(246, 150, 89, 0.15);
        }

        .row-inputs {
            display: flex;
            gap: 16px;
        }

        .btn-submit {
            width: 100%;
            background: var(--primary-color);
            color: #1A1A1A;
            border: none;
            border-radius: 14px;
            padding: 16px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            margin-top: 12px;
            box-shadow: 0 4px 12px rgba(246, 150, 89, 0.2);
        }

        .btn-submit:hover {
            background: var(--primary-hover);
            transform: translateY(-1px);
            box-shadow: 0 6px 16px rgba(246, 150, 89, 0.3);
        }

        .btn-submit:active {
            transform: translateY(0);
        }

        .icon-container {
            margin-bottom: 24px;
            display: flex;
            justify-content: center;
        }

        .status-circle {
            width: 72px;
            height: 72px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .status-circle.success {
            background: rgba(76, 175, 80, 0.15);
            border: 2px solid var(--success-color);
            color: var(--success-color);
        }

        .status-circle.error {
            background: rgba(255, 90, 95, 0.15);
            border: 2px solid var(--error-color);
            color: var(--error-color);
        }

        .svg-icon {
            width: 36px;
            height: 36px;
            fill: none;
            stroke: currentColor;
            stroke-width: 3;
            stroke-linecap: round;
            stroke-linejoin: round;
        }

        @media (max-width: 480px) {
            .card {
                padding: 32px 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="logo">Ziply</div>
            
            {{if eq .State "pay"}}
                <h1 class="title">Dividi Costo</h1>
                <p class="subtitle">Paga la tua quota della corsa di gruppo Ziply</p>

                <div class="summary-box">
                    <div class="summary-row">
                        <span class="summary-label">Corsa di Gruppo di</span>
                        <span>{{.PrenotanteName}}</span>
                    </div>
                    <div class="summary-row">
                        <span class="summary-label">Partecipanti</span>
                        <span>{{.Participants}}</span>
                    </div>
                    <div class="summary-row">
                        <span class="summary-label">Costo Totale</span>
                        <span>{{printf "%.2f" .TotalAmount}} €</span>
                    </div>
                    <div class="summary-row">
                        <span class="summary-label">Quota per persona</span>
                        <span class="amount-highlight">{{printf "%.2f" .AmountPerHead}} €</span>
                    </div>
                </div>

                <form method="POST">
                    <div class="form-group">
                        <label for="cardholder">Nome Intestatario</label>
                        <input type="text" id="cardholder" name="cardholder" placeholder="Mario Rossi" required>
                    </div>
                    <div class="form-group">
                        <label for="cardnumber">Numero Carta</label>
                        <input type="text" id="cardnumber" name="cardnumber" placeholder="•••• •••• •••• ••••" maxlength="19" required>
                    </div>
                    <div class="row-inputs">
                        <div class="form-group" style="flex: 1;">
                            <label for="expiry">Scadenza</label>
                            <input type="text" id="expiry" name="expiry" placeholder="MM/AA" maxlength="5" required>
                        </div>
                        <div class="form-group" style="flex: 1;">
                            <label for="cvv">CVV</label>
                            <input type="text" id="cvv" name="cvv" placeholder="•••" maxlength="3" required>
                        </div>
                    </div>
                    
                    <button type="submit" class="btn-submit">Paga {{printf "%.2f" .AmountPerHead}} €</button>
                </form>

                <script>
                    document.getElementById('cardnumber').addEventListener('input', function (e) {
                        let value = e.target.value.replace(/\s+/g, '').replace(/[^0-9]/gi, '');
                        let formattedValue = '';
                        for (let i = 0; i < value.length; i++) {
                            if (i > 0 && i % 4 === 0) {
                                formattedValue += ' ';
                            }
                            formattedValue += value[i];
                        }
                        e.target.value = formattedValue;
                    });

                    document.getElementById('expiry').addEventListener('input', function (e) {
                        let value = e.target.value.replace(/\s+/g, '').replace(/[^0-9]/gi, '');
                        if (value.length > 2) {
                            e.target.value = value.slice(0, 2) + '/' + value.slice(2, 4);
                        } else {
                            e.target.value = value;
                        }
                    });

                    document.getElementById('cvv').addEventListener('input', function (e) {
                        e.target.value = e.target.value.replace(/[^0-9]/gi, '');
                    });
                </script>
            {{else if eq .State "success"}}
                <div class="icon-container">
                    <div class="status-circle success">
                        <svg class="svg-icon" viewBox="0 0 24 24">
                            <polyline points="20 6 9 17 4 12"></polyline>
                        </svg>
                    </div>
                </div>
                <h1 class="title" style="color: var(--success-color);">Pagamento Completato</h1>
                <p class="subtitle">Transazione completata con successo</p>

                <div class="summary-box" style="text-align: center; padding: 24px;">
                    <p style="font-size: 15px; line-height: 1.6; color: var(--text-color);">
                        La tua quota di <strong style="color: var(--primary-color); font-size: 18px;">{{printf "%.2f" .AmountPerHead}} €</strong> è stata pagata.
                    </p>
                    <p style="font-size: 14px; color: var(--text-muted); margin-top: 12px; line-height: 1.5;">
                        L'importo è stato accreditato sul saldo di <strong>{{.PrenotanteName}}</strong>, prenotante del gruppo Ziply.
                    </p>
                </div>

                <p style="font-size: 13px; color: var(--text-muted); margin-top: 16px;">Puoi chiudere questa finestra.</p>
            {{else if eq .State "error"}}
                <div class="icon-container">
                    <div class="status-circle error">
                        <svg class="svg-icon" viewBox="0 0 24 24">
                            <circle cx="12" cy="12" r="10"></circle>
                            <line x1="12" y1="8" x2="12" y2="12"></line>
                            <line x1="12" y1="16" x2="12.01" y2="16"></line>
                        </svg>
                    </div>
                </div>
                <h1 class="title" style="color: var(--error-color);">Transazione Fallita</h1>
                <p class="subtitle">Impossibile completare il pagamento</p>

                <div class="summary-box" style="text-align: center; padding: 24px;">
                    <p style="font-size: 15px; font-weight: 500; margin-bottom: 8px; color: var(--text-color);">
                        {{.Error}}
                    </p>
                    <p style="font-size: 13px; color: var(--text-muted); line-height: 1.5;">
                        I link di pagamento Ziply hanno una validità di 10 minuti dalla loro generazione. Chiedi al prenotante di generare un nuovo link per riprovare.
                    </p>
                </div>

                <a href="javascript:location.reload()" class="btn-submit" style="display: block; text-decoration: none; line-height: 20px;">Riprova</a>
            {{end}}
            
        </div>
    </div>
</body>
</html>`))
