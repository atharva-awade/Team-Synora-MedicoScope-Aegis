<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0f766e,100:0369a1&height=230&section=header&text=MedicoScope%20Aegis&fontSize=70&fontColor=ffffff&animation=fadeIn&fontAlignY=38&desc=The%20AI-Powered%20Clinic%20in%20Your%20Pocket%20and%20Autonomous%20Diagnostic%20Guard&descAlignY=60&descSize=18" width="100%"/>

<p>
  <img src="https://img.shields.io/badge/Team-Synora-0f766e?style=for-the-badge&logo=github&logoColor=white" />
  <img src="https://img.shields.io/badge/Platform-Flutter%203.6-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Architecture-Aegis%20Clinical%20Loop-teal?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Status-Production%20Ready-34d399?style=for-the-badge" />
</p>

<p>
  <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/FastAPI-009688?style=flat-square&logo=fastapi&logoColor=white" />
  <img src="https://img.shields.io/badge/Node.js-339933?style=flat-square&logo=nodedotjs&logoColor=white" />
  <img src="https://img.shields.io/badge/Express-000000?style=flat-square&logo=express&logoColor=white" />
  <img src="https://img.shields.io/badge/MongoDB-47A248?style=flat-square&logo=mongodb&logoColor=white" />
  <img src="https://img.shields.io/badge/Groq%20Cloud-F05032?style=flat-square&logo=groq&logoColor=white" />
  <img src="https://img.shields.io/badge/TensorFlow%20Lite-FF6F00?style=flat-square&logo=tensorflow&logoColor=white" />
  <img src="https://img.shields.io/badge/Three.js%20%2F%20GLB-000000?style=flat-square&logo=threedotjs&logoColor=white" />
  <img src="https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat-square&logo=openstreetmap&logoColor=white" />
</p>

<br/>

> ### Other apps digitize symptom checklists. We built an autonomous clinical guardian.
> A multi-modal, on-device diagnostic powerhouse that screens for metabolic, cardiovascular, and respiratory conditions through non-invasive biomarkers, protected by the deterministic **Aegis Clinical Decision Guard** with real-time doctor telemetry.

</div>

---

## Table of Contents

- [The Healthcare Dilemma](#the-healthcare-dilemma)
- [What We Built](#what-we-built)
- [The Aegis Clinical Decision Engine](#the-aegis-clinical-decision-engine)
- [The Repeatable Quality Gate](#the-repeatable-quality-gate)
- [Multi-Modal Screening Arsenal](#multi-modal-screening-arsenal)
- [MindSpace & Voice Biomarkers](#mindspace--voice-biomarkers)
- [HearMe Context-Aware Medical Copilot](#hearme-context-aware-medical-copilot)
- [Interactive 3D Anatomical Visualizer](#interactive-3d-anatomical-visualizer)
- [Feature Highlights](#feature-highlights)
- [System Architecture](#system-architecture)
- [Tech Stack](#tech-stack)
- [Role-Based Access & Workflows](#role-based-access--workflows)
- [Getting Started](#getting-started)
- [Backend Services Setup](#backend-services-setup)
- [Project Structure](#project-structure)
- [Team Synora](#team-synora)

---

## The Healthcare Dilemma

Modern healthcare diagnostics suffer from three fundamental bottlenecks:

- **Asymptomatic Progression**: Conditions like Type-2 Diabetes, Hypertension, and Anemia develop quietly over years before clinical diagnosis.
- **Fragmented Evidence & Hallucinations**: Standard AI symptom checkers rely on probabilistic LLM responses without grounding in physical biomarkers, deterministic safety guardrails, or cross-modality verification.
- **The Telehealth Disconnect**: Remote patients lack affordable clinical screening tools, while physicians receive noisy, unverified subjective complaints instead of calibrated telemetry.

**MedicoScope Aegis replaces fragmented health checklists with an intelligent diagnostic command center** that combines on-device neural edge computing, digital signal processing (DSP), and the deterministic **Aegis Safety Gate** to deliver hospital-grade screening directly on commodity smartphones.

---

## What We Built

A unified, full-stack medical intelligence platform encompassing the complete patient and clinical lifecycle:

```
Capture Data  ->  Edge Inference  ->  Aegis Fusion  ->  Clinical Action  ->  Telehealth Sync
 Camera, Mic,     On-device TFLite,   Deterministic     SSE Decision         Doctor Alert,
 Vitals, Labs     DSP Signal Filter   Safety Gate       Trace & Triage       GPS & EHR Link
```

- 🩺 **Multi-Modal Screening Suite**: 7 non-invasive screening modalities covering Diabetes, Hypertension, Anemia, and Respiratory ailments.
- 🛡️ **Aegis Clinical Decision Engine**: Autonomous planning loop with deterministic safety gating, contradiction detection, and real-time SSE execution traces.
- 🧠 **MindSpace Acoustic Voice Biomarker**: Calibrated DSP voice check-ins analyzing pitch perturbation (jitter), amplitude perturbation (shimmer), HNR, and formants.
- 💬 **HearMe LLM Copilot**: Low-latency health companion powered by Groq LLaMA / OSS models grounded in the patient's verified EHR records.
- ❤️ **CardioScope Auscultation**: On-device heart sound classification (Normal vs Valvular heart disease) via MFCC feature extraction and TFLite neural nets.
- 🧬 **Interactive 3D Anatomy**: Real-time 3D rendered organ models (Heart, Eye, Pancreas, Skin) demonstrating pathological lesions.
- 🗺️ **Emergency Telehealth & Geo-Routing**: Real-time patient threshold breach alerts with live GPS coordinate dispatch to connected doctors.
- 🏆 **Health Engagement Gamification**: Synora Health Coins ecosystem rewarding preventive health habits and medication adherence.
- 🌐 **Global Accessibility**: Multi-language localization for 7 languages (English, Hindi, Tamil, Telugu, Marathi, Bengali, Kannada) and fluid Glassmorphism UI.

---

## The Repeatable Quality Gate

**A screening report can be fluent, well structured, grade-6 readable, correctly
disclaimed — and contain a haemoglobin value no sensor ever produced.** Every
readability-and-tone checker passes that document. It is also the most dangerous
thing this product can emit.

So before anything important is finalized, it goes through a gate whose entire
design rests on one line:

```
verdict = f(contentDigest, packDigest, engineVersion)
```

A pure function. No clock, no randomness, no model call. Same content and same
rules, same certificate id — on another machine, in another year.

### What it actually checks

Four of the five dimensions are what any content checker does: structure,
readability (a real Flesch–Kincaid grade, not a lookup table), clinical safety
and scope, actionability. The fifth is the one that matters.

**Evidence grounding.** Prose is treated as a set of *claims* that must *bind* to
evidence the system actually holds — reusing the `evidence.v1` envelopes and
fidelity tiers the diagnostic tools already emit.

| Sentence | Verdict |
|---|---|
| "Your blood pressure was estimated at 128/84 mmHg" | **PASS** — bound to the PPG envelope, and hedged because that envelope is `heuristic` |
| "Your blood pressure **is** 128/84 mmHg" | **BLOCK** — `GRD_NO_FIDELITY_OVERCLAIM`: a heuristic estimate narrated as a measurement |
| "Your haemoglobin is 9.2 g/dL" | **BLOCK** — `GRD_NO_UNGROUNDED_CLAIMS`: no haemoglobin measurement exists |
| "A normal range sits below 120/80" | **PASS** — classified as a *threshold* statement, not a claim about this patient |
| "low risk" over a 0.82 score | **BLOCK** — `GRD_RISK_LABEL_CONSISTENT`: not a wording defect, a wrong document |
| "Start 325 mg ferrous sulphate twice daily" | **BLOCK** — `SAF_WITHIN_SCOPE`: referral is in scope, prescribing is not |

### Rules are data, not code

Every rule lives in a versioned JSON pack. The pack may reference predicates by
id and pass arguments; it can never introduce behaviour. Load-time validation
means a pack naming an unknown predicate **throws at boot** — a rule that quietly
does nothing is worse than no rule.

That is also why the gate does not force a domain on anyone.
[`packs/generic.v1.json`](server/quality/packs/generic.v1.json) runs the same
engine, the same certificate mechanics and the same harness over a non-clinical
deliverable. The medical pack is one opinion; the engine has no clinical
vocabulary in it.

### Where the LLM is allowed to stand

An LLM is non-deterministic, so nothing an LLM decides can be part of a
repeatable verdict. Instead of putting a model inside the gate, **the agent never
scores — it writes tests.** A critic agent proposes *assertions* (a predicate id
plus arguments, never code). They are compiled against an allowlist, executed,
and reported as **advisory** — excluded from the verdict digest by construction,
unable to move PASS/WARN/BLOCK. There is an API test asserting that a *failing*
advisory finding leaves the certificate byte-identical.

The only route to authority is promotion: write it into the pack, bump the
version, and re-run the entire golden corpus. Promotion that changes an existing
verdict is **refused** until a human accepts the drift explicitly.

### The rewrite the gate is allowed to reject

When the gate blocks, an agent proposes a better draft. That is where these demos
usually turn dangerous — the model improves the prose *and* rounds a number.

So a rewrite is a proposal under contract. Before the new draft is even scored,
four things must be byte-identical: the numeric claim multiset, the risk level and
score, the cited evidence set, and the negation polarity on every clinical term.
**Prose is free, facts are frozen.** The gate can block its own fix.

### Proof, not assertion

`cd server && npm test`

| | |
|---|---|
| Aegis gate unit tests, now actually wired to CI | **57 pass** |
| Labelled golden fixtures reaching their specified verdicts | **26 / 26** |
| Certificate stability across 12 repeat evaluations each | **26 / 26 deterministic** |
| Certificate ids matching the committed lock file | **26 / 26 locked** |
| Score variance across 400 runs per fixture | **0** (bit-identical) |
| Evaluation latency | **p50 0.5 ms · p99 1.1 ms** |
| Injected defect classes caught by the mutation harness | **66 / 66 (100%)** |
| Semantically empty edits that moved a certificate | **0 / 20** |
| HTTP contract assertions | **15 / 15** |

The lock file is the anti-drift mechanism: you cannot quietly loosen a rule and
keep a green build, because every certificate id would move. The negative
controls matter as much as the catch rate — a gate that reacts to whitespace or
JSON key order would mint a new certificate for an unchanged document, making
"repeatable" false in the other direction.

### Enforcement

`POST /api/quality-gate/finalize` is the only way to sign content. The server
**re-evaluates the content it is sent** and returns `409` on BLOCK with the
remediation list. A clinician may override with a written reason, which is
appended to the same hash-chained `DecisionAudit` ledger as the clinical
decisions it governs, with their identity attached.

The app holds no rules at all. It runs a clearly-labelled offline *pre-flight*
that issues no certificate and deliberately omits the checks that actually gate a
report, because a local hint that could be read as a pass is worse than no local
hint.

Full engineering spec: **[`server/quality/SPEC.md`](server/quality/SPEC.md)**


---

## The Aegis Clinical Decision Engine

Aegis is the intelligence layer ensuring all AI decisions are **safe, explainable, and grounded in physical evidence**. The LLM is restricted to planning and synthesis, while medical safety is strictly governed by deterministic rule contracts.

```
                           +------------------------+
                           | Patient Chief Complaint |
                           +-----------+------------+
                                       |
                                       v
                    +--------------------------------------+
                    |  Aegis LLM / Keyword Triage Planner  |
                    +------------------+-------------------+
                                       |
                                       v
                    +--------------------------------------+
                    |     Evidence-Gathering Schedule      |
                    |    (Cheap/Local -> Deep Network)     |
                    +------------------+-------------------+
                                       |
                     +-----------------+-----------------+
                     |                                   |
                     v                                   v
             [ Tool Invocations ]               [ Physical Evidence ]
           Lab, PPG, Pallor, Audio             Vitals & Calibration Data
                     |                                   |
                     +-----------------+-----------------+
                                       |
                                       v
                    +--------------------------------------+
                    |   Cross-Modal Contradiction Check    |
                    |   (Discrepancy -> Trigger Re-Plan)   |
                    +------------------+-------------------+
                                       |
                                       v
                    +--------------------------------------+
                    |        Aegis Deterministic Gate      |
                    |     (Confidence Cap & Proof Hash)    |
                    +------------------+-------------------+
                                       |
                                       v
                    +--------------------------------------+
                    |   SSE Streaming Decision Trace & UI  |
                    +--------------------------------------+
```

### Key Guarantees:
1. **Zero Hallucination Safety**: If biometric data is missing, Aegis explicitly returns `not_assessed` rather than fabricating a "low risk" score.
2. **Cross-Modality Tiebreaking**: When two sensors contradict (e.g. normal symptom score but high PPG blood pressure), Aegis automatically schedules a tiebreaker modality.
3. **Fidelity-Weighted Confidence**: High-fidelity lab reports carry more mathematical weight than self-reported symptoms.
4. **Audit Proof Ledger**: Every consult generates an immutable decision trace linked into a verified ledger on the server.

---

## Multi-Modal Screening Arsenal

MedicoScope unifies 7 complementary screening vectors into standardized, actionable risk scores (**Low / Moderate / High / Critical**):

| Modality | Target Condition | Methodology & Technology | Input Source |
|:---|:---|:---|:---|
| **Lab Report Parser** | Diabetes, Anemia, Renal | Automated regex & OCR extraction of HbA1c, Fasting Glucose, Hemoglobin, RBC, Platelets | PDF Document |
| **Symptom Questionnaire** | Multi-system screening | Clinical Bayesian symptom scoring matrix with acuity triage | Interactive UI |
| **Cuff-Less Blood Pressure** | Hypertension, Hypotension | Butterworth filtered camera PPG, SDPPG pulse contour analysis, systolic/diastolic timing | Smartphone Camera + Flash |
| **Conjunctival Pallor** | Anemia | Eyelid erythema index (EI), RGB/HSV chromaticity ratios, and pallor segmentation | Front/Back Camera |
| **Retinal Fundus Analysis** | Diabetic Retinopathy | Convolutional TFLite neural network detecting microaneurysms and exudates | Fundus Lens Attachment |
| **CardioScope Auscultation** | Valvular Heart Disease, Murmurs | Audio PCM decoding, 13-band MFCC extraction, on-device `heart_model.tflite` | Microphone / Stethoscope |
| **Respiratory Acoustic** | Asthma, COPD, Bronchitis | Envelope STFT analysis, wheeze/crackle transient detection, inhale/exhale ratio | Device Microphone |

---

## MindSpace & Voice Biomarkers

MindSpace evaluates emotional well-being and depressive speech markers through acoustic digital signal processing (DSP):

- **Autocorrelation F0 Pitch Tracking**: Quantifies tonal variation and monotone pitch compression.
- **Jitter & Shimmer Perturbation**: Computes cycle-to-cycle frequency and amplitude instability.
- **Harmonics-to-Noise Ratio (HNR)**: Detects vocal breathiness and asthenia.
- **Personalized Baseline Calibration**: Scans against the patient's individual baseline voice to eliminate demographic acoustic bias.
- **Speech-to-Text Emotion Analysis**: Transcribed via Groq Whisper (`whisper-large-v3-turbo`) with supportive empathetic guidance.

---

## HearMe Context-Aware Medical Copilot

HearMe is a clinical assistant integrated into every screening result:
- **EHR Context Injection**: Chat prompts automatically ingest recent vitals, detected risks, and calibration history.
- **Ultra-Fast Streaming**: Groq Cloud inference delivers instantaneous multi-token generation.
- **Actionable Suggestions**: Recommends appropriate specialists, lifestyle modifications, and dietary guidelines based on screened conditions.

---

## Interactive 3D Anatomical Visualizer

To bridge patient understanding, MedicoScope embeds interactive 3D WebGL / GLB anatomical models:
- **3D Heart**: Inspect coronary arteries, valvular blood flow, and simulate arrhythmias.
- **3D Pancreas & Blood Vessel**: Visualize glucose crystallization and insulin regulation.
- **3D Eye & Retina**: Explore fundus layers, macula edema, and retinal micro-vascular damage.
- **Skin Lesion Explorer**: High-fidelity structural layers of cutaneous pathology.

---

## Feature Highlights

| Feature | Description |
|:---|:---|
| **🎨 Glassmorphism UI** | Liquid-glass cards with backdrop blur, smooth micro-interactions, and dark/light modes |
| **🩺 Aegis Live Consult** | Interactive step-by-step diagnostic agent with dynamic progress logs and visual hash chains |
| **📍 Telehealth & SOS Alerts** | Automatic critical vitals triggers with live GPS map coordinates dispatched to doctors |
| **🤝 Doctor-Patient Linking** | Secure 6-character code link pairing patients directly to their primary physician's portal |
| **📅 Smart Appointments** | Integrated consultation scheduler with real-time status management (Pending, Confirmed, Completed) |
| **🗺️ Nearby Hospital Locator** | Interactive OpenStreetMap radar locating medical centers and specialty clinics |
| **🏆 Synora Health Rewards** | Gamified coin rewards for regular screening, mental health check-ins, and step tracking |
| **🌐 7 Native Languages** | English, Hindi (हिंदी), Tamil (தமிழ்), Telugu (తెలుగు), Marathi (मराठी), Bengali (বাংলা), Kannada (ಕನ್ನಡ) |

---

## System Architecture

```mermaid
flowchart TD
  subgraph Client["Flutter Mobile & Web Client"]
    UI["Glassmorphic UI / Themes / Localization"]
    TFL["TFLite ML Engine (Eye, Skin, Heart)"]
    DSP["Acoustic & PPG Signal Processing"]
    THREE["3D Anatomical Model Viewer"]
  end

  subgraph FastAPI["Chatbot & AI Engine (FastAPI)"]
    HEAR["HearMe LLM Streamer"]
    AEGIS_C["Aegis Goal-Driven Consult Planner"]
    WHISP["Groq Whisper Audio Transcription"]
    GROQ[("Groq Cloud LLaMA / OSS 120B")]
  end

  subgraph NodeServer["Core Backend API (Node.js & Express)"]
    AUTH["JWT Auth & Role Guard"]
    TOOLS["Aegis Tool Execution Surface"]
    GATE["Aegis Deterministic Safety Gate"]
    EPISODES["Clinical Case Episodes & EHR"]
    ALERTS["Live Vitals & Location Alert Dispatch"]
  end

  subgraph Database["Data Persistence"]
    MONGO[("MongoDB Atlas Database")]
  end

  UI -->|"REST / Auth / Records"| NodeServer
  UI -->|"Live Chat & Consult SSE"| FastAPI
  UI --> DSP
  UI --> TFL
  UI --> THREE

  FastAPI -->|"Tool Invocations & Submissions"| TOOLS
  FastAPI --> GROQ
  FastAPI --> WHISP

  NodeServer --> GATE
  NodeServer --> EPISODES
  NodeServer --> ALERTS
  NodeServer --> MONGO
```

---

## Tech Stack

<table>
<tr>
<td valign="top" width="50%">

### Frontend & Edge ML
| Component | Technology |
|:---|:---|
| **Framework** | Flutter 3.6.0 (Dart 3.6.0) |
| **State Management** | Provider Architecture |
| **On-Device Inference** | `tflite_flutter` (Edge Models) |
| **Signal Processing** | `fftea`, custom Butterworth DSP |
| **3D Rendering** | `model_viewer_plus` (Three.js / GLB) |
| **Mapping & GPS** | `flutter_map` (OpenStreetMap) + `geolocator` |
| **Typography & Styling** | Google Fonts (Inter / Outfit) + Flutter Animate |
| **PDF Extraction** | `syncfusion_flutter_pdf` |

</td>
<td valign="top" width="50%">

### Backend & Cloud Services
| Component | Technology |
|:---|:---|
| **Core API Server** | Node.js (v20+) + Express |
| **AI Microservice** | Python 3.11 + FastAPI + Uvicorn |
| **LLM Inference** | Groq Cloud SDK (`openai/gpt-oss-120b`) |
| **Speech-to-Text** | Groq Whisper (`whisper-large-v3-turbo`) |
| **Database** | MongoDB Atlas / Mongoose ORM |
| **Authentication** | JSON Web Tokens (JWT) + bcrypt |
| **Real-time Protocol** | Server-Sent Events (SSE) & WebSockets |
| **Cloud Deployment** | Render Cloud PaaS |

</td>
</tr>
</table>

---

## Role-Based Access & Workflows

MedicoScope provides tailored interfaces for each stakeholder in the care continuum:

| Feature Area | 👤 Patient | 🩺 Doctor | 🛡️ Admin |
|:---|:---:|:---:|:---:|
| Multi-Modal Screenings | ✅ Run Scans & View History | ✅ Review Clinical Telemetry | ❌ |
| Aegis Diagnostic Consult | ✅ Interactive Consult | ✅ View Step Traces & Proofs | ❌ |
| MindSpace & Chatbot | ✅ Full Voice & Chat | ✅ View Sentiment Trends | ❌ |
| Live Vitals Alerts | ✅ Emergency SOS Push | ✅ Receive Real-Time Map Alerts | ❌ |
| Clinical Case Management | ❌ | ✅ Manage Linked Patients & Notes | ❌ |
| Appointment Management | ✅ Book & Cancel | ✅ Confirm & Complete | ✅ Global Audit |
| Gamification & Coins | ✅ Earn & Redeem Rewards | ❌ | ✅ Configure Rewards |
| System Statistics & Logs | ❌ | ❌ | ✅ Full Infrastructure Telemetry |

---

## Getting Started

### Prerequisites
- **Flutter SDK**: 3.6.0 or higher ([Install Guide](https://flutter.dev/docs/get-started/install))
- **Node.js**: 20.x or higher
- **Python**: 3.10 or higher
- **Android SDK & NDK**: Version `28.0.12674087` or `27.0.12077973`

### 1. Clone the Repository
```bash
git clone https://github.com/atharva-awade/Team-Synora-MedicoScope-Aegis.git
cd Team-Synora-MedicoScope-Aegis
```

### 2. Configure Client Dependencies
```bash
flutter pub get
```

### 3. Verify ML & 3D Assets
Ensure required models are present in the assets folder:
```
assets/
├── models/
│   ├── eye_float16.tflite
│   ├── eye_float32.tflite
│   ├── skin_float16.tflite
│   └── heart_model.tflite
└── 3d_models/
    ├── heart.glb
    └── skin.glb
```

### 4. Run the Flutter App
```bash
flutter run
```

---

## Backend Services Setup

### Node.js API Server (`server/`)
1. Navigate to the server folder:
   ```bash
   cd server
   npm install
   ```
2. Create `.env` file:
   ```env
   PORT=5000
   NODE_ENV=development
   MONGODB_URI=mongodb://127.0.0.1:27017/medicoscope
   JWT_SECRET=your_jwt_secret_token
   SERVICE_KEY=your_shared_service_secret
   ```
3. Start the server:
   ```bash
   npm start
   ```

### Python FastAPI Chatbot & Aegis Service (`chatbot/`)
1. Navigate to the chatbot directory:
   ```bash
   cd chatbot
   pip install -r requirements.txt
   ```
2. Create `.env` file:
   ```env
   GROQ_API_KEY=your_groq_api_key
   GROQ_MODEL=openai/gpt-oss-120b
   BACKEND_URL=http://localhost:5000/api
   SERVICE_KEY=your_shared_service_secret
   ```
3. Run the microservice:
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

---

## Project Structure

```
Team-Synora-MedicoScope-Aegis/
├── android/                    # Android native Gradle configuration & permissions
├── assets/
│   ├── 3d_models/             # Interactive 3D anatomical models (.glb)
│   ├── icons/                 # High-resolution clinical vectors & iconography
│   ├── images/                # UI illustrations and onboarding assets
│   └── models/                # Quantized TFLite edge neural network models
├── chatbot/                   # Python FastAPI AI & Aegis consult service
│   ├── aegis_consult.py       # Aegis planner, contradiction resolver & SSE stream
│   ├── main.py                # HearMe LLM streaming, MindSpace voice transcription
│   └── requirements.txt       # Python dependencies (FastAPI, Groq, LangChain)
├── lib/
│   ├── core/                  # Design tokens, AppTheme, localization, constants
│   ├── data/                  # Disease reference datasets & symptom score matrices
│   ├── models/                # Data models (User, Doctor, Patient, DiseaseRiskResult)
│   ├── screens/               # Feature UI screens (Auth, Dashboards, MindSpace, Map)
│   ├── services/              # API clients, Aegis gate, TFLite inference, DSP analyzers
│   └── main.dart              # Application entrypoint & state providers
├── server/                    # Node.js Express REST API server
│   ├── quality/               # Aegis Quality Gate: engine, policy packs, corpus, harnesses
│   │   ├── lib/               # canonical hashing, claim binding, predicates, engine
│   │   ├── packs/             # versioned rule sets as DATA (medical + domain-neutral)
│   │   ├── corpus/            # 26 labelled fixtures + certificate lock + conformance vectors
│   │   ├── harness/           # verify / bench / fuzz / parity / promote / route-smoke
│   │   └── SPEC.md            # engine specification
│   ├── src/
│   │   ├── config/            # MongoDB database connection pool
│   │   ├── middleware/        # JWT auth verify, role check, rate limiting
│   │   ├── models/            # Mongoose schemas (User, Episode, Detection, Alert)
│   │   ├── routes/            # REST endpoints (Auth, Doctors, Aegis, Vitals)
│   │   └── index.js           # Server bootstrap & route registration
│   └── package.json
└── README.md                  # Complete project documentation
```

---

## Team Synora

Developed with precision and passion for healthcare accessibility by **Team Synora**:

- **Atharva Awade** ([@atharva-awade](https://github.com/atharva-awade))
- **Pratik Kumbhar** ([@Pratik-1213](https://github.com/Pratik-1213))

<div align="center">

<br/>

**Transforming preventive healthcare through autonomous edge intelligence.**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0369a1,100:0f766e&height=110&section=footer" width="100%"/>

</div>
