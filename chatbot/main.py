import os
import re
import json
import uuid
import random
import asyncio
import base64
from datetime import datetime, timedelta
from typing import Optional, AsyncGenerator

import httpx
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from dotenv import load_dotenv
from groq import Groq
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.messages import HumanMessage, AIMessage
from langchain_groq import ChatGroq

load_dotenv()

app = FastAPI(title="MedicoScope Medical Assistant", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Dual-Engine Clients (Google Gemini Primary + Groq Fail-Safe) ───
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest")

def _get_gemini_candidates() -> list[str]:
    """Returns candidate Gemini model IDs in priority order."""
    candidates = []
    for m in [GEMINI_MODEL, "gemini-flash-lite-latest", "gemini-3.8-flash", "gemini-flash-latest"]:
        if m and m not in candidates:
            candidates.append(m)
    return candidates

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")

groq_client = None
if GROQ_API_KEY:
    try:
        groq_client = Groq(api_key=GROQ_API_KEY)
    except Exception as e:
        print(f"Warning: Groq client init failed: {e}")

llm = None
llm_streaming = None
if GROQ_API_KEY:
    try:
        llm = ChatGroq(
            model=GROQ_MODEL,
            api_key=GROQ_API_KEY,
            temperature=0.7,
            max_tokens=1024,
        )
        llm_streaming = ChatGroq(
            model=GROQ_MODEL,
            api_key=GROQ_API_KEY,
            temperature=0.7,
            max_tokens=1024,
            streaming=True,
        )
    except Exception as e:
        print(f"Warning: ChatGroq init failed: {e}")

# ── Config ─────────────────────────────────────────────────────────────────
BACKEND_URL = os.getenv("BACKEND_URL", "https://medicoscope-backend-efmsp2t7cq-el.a.run.app/api")
# Shared secret for service-to-service calls (vitals ingest). Must match the
# Node server's SERVICE_KEY. If unset, the Node side warns and allows.
SERVICE_KEY = os.getenv("SERVICE_KEY", "")


def _service_headers() -> dict:
    return {"X-Service-Key": SERVICE_KEY} if SERVICE_KEY else {}


async def _backend_post(path: str, payload: dict, headers: dict | None = None) -> None:
    """Best-effort POST to the Node backend; never raises into the request path.
    Logs a non-2xx response (e.g. a SERVICE_KEY 401) instead of swallowing it,
    so a mis-set key can't silently drop persisted alerts."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(f"{BACKEND_URL}{path}", json=payload, headers=headers or {})
            if resp.status_code >= 400:
                print(f"Warning: backend POST {path} -> HTTP {resp.status_code}: {resp.text[:200]}")
    except Exception as e:
        print(f"Warning: backend POST {path} failed: {e}")


async def _backend_patch(path: str, payload: dict, headers: dict | None = None) -> None:
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            await client.patch(f"{BACKEND_URL}{path}", json=payload, headers=headers or {})
    except Exception as e:
        print(f"Warning: backend PATCH {path} failed: {e}")


# ── In-memory stores ────────────────────────────────────────────────────────
# NOTE: these are TRANSIENT working caches only. The durable source of truth is
# MongoDB via the Node backend - chat history persists to /api/chat, and vitals
# sessions/alerts persist to /api/vitals. The dicts below survive only within a
# single process lifetime and are repopulated from the backend on cold start.
session_histories: dict[str, list] = {}

# ── Vitals in-memory stores ─────────────────────────────────────────────────
vitals_sessions: dict[str, dict] = {}   # session_id -> live simulator state (ephemeral by design)
vitals_alerts: dict[str, list] = {}     # short-lived cache; Mongo is source of truth

# ── Medical Knowledge Base ──────────────────────────────────────────────────
MEDICAL_DATA = {
    "skin_diseases": {
        "eczema": {"symptoms": ["itchy skin", "red patches", "dry skin", "inflammation"], "severity": "moderate", "advice": "Use moisturizers, avoid triggers, consider topical corticosteroids"},
        "psoriasis": {"symptoms": ["scaly patches", "red skin", "itching", "thick silvery scales"], "severity": "moderate", "advice": "Phototherapy, topical treatments, systemic medications for severe cases"},
        "acne": {"symptoms": ["pimples", "blackheads", "whiteheads", "oily skin"], "severity": "mild", "advice": "Gentle cleansing, benzoyl peroxide, retinoids, consult dermatologist if severe"},
        "dermatitis": {"symptoms": ["skin rash", "blisters", "itching", "swelling"], "severity": "mild-moderate", "advice": "Identify and avoid allergens, use antihistamines and topical steroids"},
    },
    "chest_diseases": {
        "asthma": {"symptoms": ["wheezing", "shortness of breath", "chest tightness", "coughing"], "severity": "moderate-severe", "advice": "Use inhaler, avoid triggers, seek emergency care for severe attacks"},
        "pneumonia": {"symptoms": ["fever", "cough with phlegm", "chest pain", "difficulty breathing"], "severity": "severe", "advice": "Seek immediate medical care, antibiotics may be needed, rest and fluids"},
        "bronchitis": {"symptoms": ["persistent cough", "mucus production", "fatigue", "chest discomfort"], "severity": "moderate", "advice": "Rest, fluids, humidifier, see doctor if symptoms last >3 weeks"},
        "copd": {"symptoms": ["chronic cough", "shortness of breath", "wheezing", "frequent respiratory infections"], "severity": "severe", "advice": "Quit smoking, bronchodilators, pulmonary rehabilitation, see pulmonologist"},
    },
    "brain_diseases": {
        "migraine": {"symptoms": ["severe headache", "nausea", "sensitivity to light", "visual disturbances"], "severity": "moderate", "advice": "Rest in dark room, OTC pain relievers, preventive medications for frequent migraines"},
        "tension_headache": {"symptoms": ["dull aching head pain", "tightness around forehead", "tenderness in scalp"], "severity": "mild", "advice": "Stress management, OTC pain relievers, adequate sleep, regular exercise"},
        "concussion": {"symptoms": ["headache", "confusion", "dizziness", "nausea", "memory problems"], "severity": "severe", "advice": "Seek immediate medical attention, rest, avoid screens, gradual return to activities"},
        "meningitis": {"symptoms": ["severe headache", "stiff neck", "high fever", "sensitivity to light", "nausea"], "severity": "critical", "advice": "EMERGENCY: Seek immediate medical care. This is potentially life-threatening."},
    },
}

# ── Language Instructions ───────────────────────────────────────────────────
LANGUAGE_INSTRUCTIONS = {
    "en": "Respond in English.",
    "hi": "Respond in Hindi (हिंदी में उत्तर दें).",
    "ta": "Respond in Tamil (தமிழில் பதிலளிக்கவும்).",
    "te": "Respond in Telugu (తెలుగులో సమాధానం ఇవ్వండి).",
    "mr": "Respond in Marathi (मराठीत उत्तर द्या).",
    "bn": "Respond in Bengali (বাংলায় উত্তর দিন).",
    "kn": "Respond in Kannada (ಕನ್ನಡದಲ್ಲಿ ಉತ್ತರಿಸಿ).",
}

# ── Pydantic Models ─────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"
    language: str = "en"
    medical_context: Optional[str] = None
    patient_profile: Optional[str] = None

class RewardRedeemRequest(BaseModel):
    reward_type: str
    language: str = "en"


# ── Helper Functions ────────────────────────────────────────────────────────

def get_session_history(session_id: str) -> list:
    if session_id not in session_histories:
        session_histories[session_id] = []
    return session_histories[session_id]


def sanitize_ai_output(text: str, patient_name: str = "") -> str:
    """Sanitizes AI responses to guarantee a polished, user-centric mobile experience:
    1. Removes any hallucinated bracket placeholders like [Your Name], [Name], [Patient Name].
    2. Strips raw markdown table syntax (| col | col |) and long divider dashes.
    3. Formats clean bullet points and natural greeting.
    """
    if not text:
        return ""
    cleaned = text
    # Replace [Your Name], [Name], [User], [Patient] with patient's real name or empty
    rep_name = patient_name.strip() if patient_name and patient_name.lower() not in ["anonymous", "patient", "not specified"] else ""
    cleaned = re.sub(r'\[\s*(?:Your\s+Name|Name|Patient(?:\s+Name)?|User)\s*\]', rep_name, cleaned, flags=re.IGNORECASE)
    # Strip long runs of dashes or underscores that break chat bubbles (e.g. --- or ____)
    cleaned = re.sub(r'[-_]{4,}', '', cleaned)
    # Clean broken markdown table pipes and separators
    cleaned = re.sub(r'\|\s*[-:]+\s*\|', '', cleaned)
    cleaned = re.sub(r'\n\s*\|\s*', '\n• ', cleaned)
    cleaned = cleaned.replace(' | ', ' • ')
    # Clean multiple empty lines
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)
    return cleaned.strip()


def _build_system_prompt(
    lang_instruction: str,
    medical_json: str,
    medical_context: Optional[str],
    patient_profile: Optional[str],
) -> str:
    """Build the full system prompt with strict identity, zero-placeholder, and mobile card rules."""
    patient_name = ""
    if patient_profile:
        name_match = re.search(r'\bName:\s*([^\r\n,]+)', patient_profile, re.IGNORECASE)
        if name_match:
            candidate = name_match.group(1).strip()
            if candidate.lower() not in ["anonymous", "not specified", "patient", "none", "n/a", ""]:
                patient_name = candidate

    name_instruction = (
        f'The patient\'s name is "{patient_name}". Greet them naturally by their first name (e.g., "Hello {patient_name}").'
        if patient_name
        else 'The patient\'s name is not provided. Greet them warmly with "Hello!" or "Welcome back!" without using any name or placeholder.'
    )

    system_template = f"""You are MediBot, a dedicated clinical and healthcare AI assistant for the MedicoScope medical application.
Your core objective is to assist patients with medical, health, wellness, symptom triage, vital signs, anatomy, lifestyle guidance, and app-related health scans/records.

CRITICAL IDENTITY & PERSONA RULES (ABSOLUTE REQUIREMENT):
1. ZERO-PLACEHOLDER GUARANTEE: NEVER output placeholder text such as "[Your Name]", "[Name]", "[Patient Name]", "[Date]", or any brackets "[...]".
2. NAME RESOLUTION: {name_instruction} NEVER guess, invent, or write "[Your Name]".
3. NO MARKDOWN TABLES & NO LONG DASH LINES:
   - NEVER use markdown tables (no '|' pipes). Mobile screens cannot render tables and they overflow and break.
   - NEVER output horizontal lines of dashes (---) or underscores (___).
   - ALWAYS format structured information using bold title cards and clean bullet points (•).
4. CLINICAL DATA GROUNDING:
   - Actively reference the patient's real data from PATIENT DATA below (e.g. recent skin scans, BP values like 143/87, blood group A+, lab reports).
   - Explain what their specific numbers mean, reassure them about manageable risks, and provide clear, gentle, actionable lifestyle and medical next steps.

STRICT DOMAIN BOUNDARY & REFUSAL POLICY:
1. You must ONLY answer questions directly related to medicine, health, human biology, symptoms, vital signs, anatomy, wellness, fitness, nutrition, mental health, medical reports/scans, medications, doctors, clinics, appointments, or MedicoScope features.
2. You are STRICTLY FORBIDDEN from answering any questions outside the medical and healthcare domain.
3. Specifically, NEVER answer requests for computer programming, software development, coding, writing scripts, debugging code, computer algorithms, mathematics, academic homework, creative fiction writing, gaming, or financial/investment advice.
4. If a user asks a non-health question, POLITELY AND FIRMLY DECLINE to answer. State that you are MediBot, MedicoScope's specialized medical AI assistant, and invite them to ask a health-related question instead.

CLINICAL & EMOTIONAL INTELLIGENCE RULES:
1. DEEP EMPATHY & EMOTIONAL RESONANCE: Speak with warmth, compassion, hope, and personal care. Never give dry, robotic, or cold answers.
2. VALIDATE ANXIETY & FEAR: If the patient has a high-confidence condition (e.g., melanoma, high BP, lung opacity), validate their natural worry with comforting reassurance, explain what it means in clear terms without terrifying them, and outline positive, calm, actionable next steps.
3. FINDING NEARBY DOCTORS (NO PINCODES / NO HALLUCINATED NAMES):
   - MedicoScope has a built-in real-time GPS "Find Nearby Doctors" module on the Patient Dashboard and App Drawer.
   - NEVER ask the user for a pincode, zip code, or address.
   - NEVER fabricate or hallucinate doctor names from different cities.
   - Guide them to use MedicoScope's built-in "Find Nearby Doctors" feature with device GPS, interactive maps, specialty filters, direct calling, and Google Maps navigation.
4. CLEAN STRUCTURED FORMATTING: Always format answers cleanly using Markdown with bold headings, bullet points (•), clean spacing, and supportive emojis for optimal readability.
5. CLINICAL SAFETY: Never give a definitive diagnosis—provide educational context and advise seeing a certified doctor. For severe emergencies (acute chest pain, stroke symptoms, respiratory distress), advise immediate emergency care.
6. {lang_instruction}

MEDICAL KNOWLEDGE BASE:
{medical_json}
"""
    if patient_profile:
        escaped_profile = patient_profile.replace("{", "{{").replace("}", "}}")
        system_template += f"\n\nPATIENT PROFILE:\n{escaped_profile}"

    if medical_context:
        escaped_context = medical_context.replace("{", "{{").replace("}", "}}")
        system_template += f"\n\nPATIENT DATA (from MedicoScope app - use this to answer patient questions):\n{escaped_context}"

    return system_template


# ── Dual-Engine Invocation Helpers ──────────────────────────────────────────

async def _gemini_generate(system_prompt: str, user_input: str, history: list) -> str:
    """Calls Google Gemini via REST API with automated candidate fallback."""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY not configured")
    
    contents = []
    for msg in history[-10:]:
        role = "user" if isinstance(msg, HumanMessage) else "model"
        contents.append({"role": role, "parts": [{"text": str(msg.content)}]})
    contents.append({"role": "user", "parts": [{"text": user_input}]})
    
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": contents,
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 1024,
        }
    }
    
    last_err = None
    for model_id in _get_gemini_candidates():
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_id}:generateContent?key={GEMINI_API_KEY}"
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(url, json=payload)
                if resp.status_code == 200:
                    data = resp.json()
                    candidates = data.get("candidates", [])
                    if candidates:
                        text = candidates[0].get("content", {}).get("parts", [{}])[0].get("text", "")
                        if text:
                            return text
                else:
                    last_err = f"Gemini error ({model_id} HTTP {resp.status_code}): {resp.text[:200]}"
        except Exception as e:
            last_err = f"Gemini error ({model_id}): {e}"
            continue
    raise RuntimeError(last_err or "Gemini returned empty candidates")


async def _gemini_stream(system_prompt: str, user_input: str, history: list) -> AsyncGenerator[str, None]:
    """Streams token chunks from Google Gemini via SSE with automated candidate fallback."""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY not configured")
        
    contents = []
    for msg in history[-10:]:
        role = "user" if isinstance(msg, HumanMessage) else "model"
        contents.append({"role": role, "parts": [{"text": str(msg.content)}]})
    contents.append({"role": "user", "parts": [{"text": user_input}]})
    
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": contents,
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 1024,
        }
    }
    
    connected = False
    for model_id in _get_gemini_candidates():
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_id}:streamGenerateContent?alt=sse&key={GEMINI_API_KEY}"
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                async with client.stream("POST", url, json=payload) as stream_resp:
                    if stream_resp.status_code == 200:
                        connected = True
                        buffer = ""
                        async for chunk in stream_resp.aiter_text():
                            buffer += chunk
                            while "\n" in buffer:
                                line, buffer = buffer.split("\n", 1)
                                line = line.strip()
                                if line.startswith("data: "):
                                    data_str = line[6:].strip()
                                    if data_str == "[DONE]":
                                        break
                                    try:
                                        item = json.loads(data_str)
                                        cands = item.get("candidates", [])
                                        if cands:
                                            parts = cands[0].get("content", {}).get("parts", [])
                                            for p in parts:
                                                t = p.get("text", "")
                                                if t:
                                                    yield t
                                    except Exception:
                                        pass
                        return
        except Exception:
            continue
    if not connected:
        raise RuntimeError("All Gemini streaming model candidates failed to connect")


async def execute_chat(system_template: str, user_input: str, history: list, patient_name: str = "") -> str:
    """Executes chat with Google Gemini 2.5 Flash Primary and Groq Fail-Safe."""
    # 1. Primary: Google Gemini 2.5 Flash
    if GEMINI_API_KEY:
        try:
            reply = await _gemini_generate(system_template, user_input, history)
            if reply and reply.strip():
                return sanitize_ai_output(reply, patient_name)
        except Exception as e:
            print(f"[FAIL-SAFE TRIGGERED] Gemini primary failed: {e}. Falling back to Groq...")

    # 2. Fail-Safe: Groq Llama-3.3-70B
    if llm:
        try:
            prompt = ChatPromptTemplate.from_messages([
                ("system", system_template),
                MessagesPlaceholder(variable_name="history"),
                ("human", "{input}"),
            ])
            chain = prompt | llm
            response = await chain.ainvoke({"input": user_input, "history": history})
            return sanitize_ai_output(response.content, patient_name)
        except Exception as e:
            print(f"[FAIL-SAFE] Groq fallback failed: {e}")

    raise HTTPException(status_code=503, detail="Both Gemini primary and Groq fail-safe engines are temporarily unavailable.")


async def stream_chat(system_template: str, user_input: str, history: list, patient_name: str = "") -> AsyncGenerator[str, None]:
    """Streams chat tokens with Google Gemini 2.5 Flash Primary and Groq Fail-Safe."""
    # 1. Primary: Google Gemini 2.5 Flash Streaming
    if GEMINI_API_KEY:
        try:
            has_yielded = False
            async for token in _gemini_stream(system_template, user_input, history):
                has_yielded = True
                yield token
            if has_yielded:
                return
        except Exception as e:
            print(f"[FAIL-SAFE TRIGGERED] Gemini streaming failed: {e}. Falling back to Groq streaming...")

    # 2. Fail-Safe: Groq Streaming
    if llm_streaming:
        try:
            prompt = ChatPromptTemplate.from_messages([
                ("system", system_template),
                MessagesPlaceholder(variable_name="history"),
                ("human", "{input}"),
            ])
            chain = prompt | llm_streaming
            async for chunk in chain.astream({"input": user_input, "history": history}):
                token = chunk.content
                if token:
                    yield token
            return
        except Exception as e:
            print(f"[FAIL-SAFE] Groq streaming failed: {e}")

    yield "I apologize, but both the primary and backup medical AI engines are temporarily warming up. Please try asking again in a moment."


async def execute_text_generation(prompt: str, system_prompt: str = "You are a clinical AI assistant.") -> str:
    """Invokes Google Gemini Primary with Groq Fail-Safe for single prompt tasks."""
    if GEMINI_API_KEY:
        for model_id in _get_gemini_candidates():
            try:
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_id}:generateContent?key={GEMINI_API_KEY}"
                payload = {
                    "systemInstruction": {"parts": [{"text": system_prompt}]},
                    "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                    "generationConfig": {"temperature": 0.6, "maxOutputTokens": 1024}
                }
                async with httpx.AsyncClient(timeout=15.0) as client:
                    resp = await client.post(url, json=payload)
                    if resp.status_code == 200:
                        data = resp.json()
                        cands = data.get("candidates", [])
                        if cands:
                            text = cands[0].get("content", {}).get("parts", [{}])[0].get("text", "")
                            if text and text.strip():
                                return text.strip()
            except Exception as e:
                print(f"[FAIL-SAFE TRIGGERED] Gemini ({model_id}) text gen failed: {e}. Trying next...")
                continue

    if llm:
        try:
            res = await llm.ainvoke(prompt)
            return res.content.strip()
        except Exception as e:
            print(f"Groq text gen fallback failed: {e}")
            
    return ""


def clean_doctor_report(text: str) -> str:
    """Strips all markdown asterisks, broken table lines, and hashes, formatting into clean clinical text."""
    if not text:
        return ""
    # Strip markdown bold/italic asterisks: **text** or *text* or ***text***
    text = re.sub(r'\*{1,3}([^*\r\n]+?)\*{1,3}', r'\1', text)
    # Strip any remaining solitary asterisks
    text = text.replace('*', '')
    # Replace markdown bullet dashes or pluses with clean bullet points
    text = re.sub(r'^[ \t]*[-+•]\s*', '• ', text, flags=re.MULTILINE)
    # Remove markdown header hashes
    text = re.sub(r'^[ \t]*#{1,6}\s*', '', text, flags=re.MULTILINE)
    # Remove excessive horizontal rules
    text = re.sub(r'[-_]{4,}', '', text)
    # Strip double/triple empty lines
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


# ── Routes ──────────────────────────────────────────────────────────────────

@app.get("/")
@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "medicoscope-ai-engine",
        "primary_engine": f"Google Gemini ({GEMINI_MODEL})" if GEMINI_API_KEY else "unconfigured",
        "fail_safe_engine": f"Groq ({GROQ_MODEL})" if GROQ_API_KEY else "unconfigured"
    }


# ── Aegis consult loop (agentic orchestration + SSE decision-trace) ──────────
from aegis_consult import ConsultRequest, run_consult


@app.post("/aegis/consult")
async def aegis_consult(req: ConsultRequest):
    """Streams the live agent decision-trace as Server-Sent Events.

    The LLM plans/explains only; the deterministic Aegis gate (in the Node
    backend) decides safety and executes/blocks actions. Degrades to a
    deterministic planner if no LLM key is present, so it always completes.
    """
    return StreamingResponse(run_consult(req), media_type="text/event-stream")


# ── Chat (non-streaming) ───────────────────────────────────────────────────

@app.post("/chat")
async def chat(req: ChatRequest):
    try:
        history = get_session_history(req.session_id)
        lang_instruction = LANGUAGE_INSTRUCTIONS.get(req.language, LANGUAGE_INSTRUCTIONS["en"])

        # Escape curly braces in JSON so LangChain doesn't treat them as template vars
        medical_json = json.dumps(MEDICAL_DATA, indent=2).replace("{", "{{").replace("}", "}}")

        system_template = _build_system_prompt(lang_instruction, medical_json, req.medical_context, req.patient_profile)

        # Extract patient name for personalization
        patient_name = ""
        if req.patient_profile:
            name_m = re.search(r'\bName:\s*([^\r\n,]+)', req.patient_profile, re.IGNORECASE)
            if name_m:
                patient_name = name_m.group(1).strip()

        reply = await execute_chat(system_template, req.message, history, patient_name)

        history.append(HumanMessage(content=req.message))
        history.append(AIMessage(content=reply))

        # Keep history manageable
        if len(history) > 20:
            session_histories[req.session_id] = history[-20:]

        return {"response": reply, "session_id": req.session_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Chat (streaming SSE) ───────────────────────────────────────────────────

@app.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    async def event_generator():
        try:
            history = get_session_history(req.session_id)
            lang_instruction = LANGUAGE_INSTRUCTIONS.get(req.language, LANGUAGE_INSTRUCTIONS["en"])

            medical_json = json.dumps(MEDICAL_DATA, indent=2).replace("{", "{{").replace("}", "}}")

            system_template = _build_system_prompt(lang_instruction, medical_json, req.medical_context, req.patient_profile)

            # Extract patient name for personalization
            patient_name = ""
            if req.patient_profile:
                name_m = re.search(r'\bName:\s*([^\r\n,]+)', req.patient_profile, re.IGNORECASE)
                if name_m:
                    patient_name = name_m.group(1).strip()

            full_response = ""

            async for token in stream_chat(system_template, req.message, history, patient_name):
                if token:
                    full_response += token
                    yield f"data: {json.dumps({'token': token})}\n\n"

            clean_full = sanitize_ai_output(full_response, patient_name)
            history.append(HumanMessage(content=req.message))
            history.append(AIMessage(content=clean_full))

            if len(history) > 20:
                session_histories[req.session_id] = history[-20:]

            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


# ── Mental Health Analysis ──────────────────────────────────────────────────

async def anonymize_third_party_names(text: str, patient_name: str = "") -> str:
    """Scrub third-party individuals' names from MindSpace transcripts or clinical reports
    before sending to the doctor side so personal identities mentioned during emotional
    check-ins are never revealed to healthcare providers."""
    if not text or not text.strip():
        return text
    try:
        scrub_prompt = f"""You are a patient privacy and confidentiality compliance officer.
Your task is to sanitize and anonymize ANY names of third-party individuals (e.g. friends, partners, family members, coworkers, bosses, acquaintances) mentioned in the text below.
Replace each specific person's name with an appropriate neutral tag such as [Friend], [Family Member], [Colleague], [Partner], or [Individual].
IMPORTANT RULES:
- Do NOT redact the patient's own name ({patient_name}) if they refer to themselves.
- Do NOT alter clinical descriptions, symptoms, emotions, medical terminology, or medications.
- Output ONLY the sanitized text, without any introductory or concluding comments.

Text to sanitize:
{text}"""
        sanitized = await execute_text_generation(scrub_prompt, system_prompt="You are a patient privacy and confidentiality compliance officer.")
        if sanitized and len(sanitized) > 5:
            return sanitized
    except Exception as e:
        print(f"Privacy anonymization fallback: {e}")

    # Regex heuristic fallback
    sanitized = text
    sanitized = re.sub(
        r'\b(friend|boss|coworker|colleague|partner|roommate|neighbor|brother|sister|mother|father|mom|dad|uncle|aunt|cousin)\s+([A-Z][a-z]+)\b',
        r'\1 [Individual]',
        sanitized,
        flags=re.IGNORECASE
    )
    return sanitized


@app.post("/mental-health/analyze")
async def analyze_mental_health(
    audio: UploadFile = File(...),
    patient_id: str = Form(...),
    patient_name: str = Form(...),
    doctor_id: Optional[str] = Form(None),
    language: str = Form("en"),
    auth_token: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    location_label: Optional[str] = Form(None),
    maps_url: Optional[str] = Form(None),
    voice_marker_score: Optional[float] = Form(None),
    voice_marker_headline: Optional[str] = Form(None),
):
    try:
        # Save audio temporarily
        audio_bytes = await audio.read()
        temp_path = f"/tmp/mental_health_{uuid.uuid4()}.m4a"
        with open(temp_path, "wb") as f:
            f.write(audio_bytes)

        # Transcribe audio with dual-engine fail-safe
        transcript = ""
        # 1. Primary fast transcription: Groq Whisper Large v3 Turbo
        if groq_client:
            try:
                with open(temp_path, "rb") as audio_file:
                    transcription = groq_client.audio.transcriptions.create(
                        file=("audio.m4a", audio_file),
                        model="whisper-large-v3-turbo",
                        language=language if language != "en" else None,
                    )
                transcript = transcription.text.strip()
            except Exception as w_err:
                print(f"[WHISPER FAIL-SAFE] Groq Whisper failed: {w_err}. Trying Gemini 2.5 Flash audio...")

        # 2. Backup transcription: Google Gemini 2.5 Flash Multimodal Audio
        if not transcript and GEMINI_API_KEY:
            try:
                raw_b64 = base64.b64encode(audio_bytes).decode("utf-8")
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
                payload = {
                    "contents": [{
                        "role": "user",
                        "parts": [
                            {"text": "Transcribe this audio check-in accurately in the original spoken language. Output only the transcription, nothing else."},
                            {"inline_data": {"mime_type": "audio/mp4", "data": raw_b64}}
                        ]
                    }],
                    "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1024}
                }
                async with httpx.AsyncClient(timeout=25.0) as client:
                    resp = await client.post(url, json=payload)
                    if resp.status_code == 200:
                        data = resp.json()
                        cands = data.get("candidates", [])
                        if cands:
                            transcript = cands[0].get("content", {}).get("parts", [{}])[0].get("text", "").strip()
            except Exception as g_err:
                print(f"Gemini audio transcription failed: {g_err}")

        if not transcript:
            transcript = "Patient shared emotional feelings and mental state during this voice check-in."

        lang_instruction = LANGUAGE_INSTRUCTIONS.get(language, LANGUAGE_INSTRUCTIONS["en"])

        # Clean up temp file
        try:
            os.remove(temp_path)
        except:
            pass

        # User-facing empathetic response (Gemini 2.5 Flash Primary + Groq Fail-Safe)
        user_prompt = f"""You are a compassionate mental health companion for MedicoScope MindSpace.
A user just shared their feelings through a voice check-in. Here's their transcription:

"{transcript}"

Provide a warm, empathetic, and detailed response that:
1. Acknowledges and validates their specific feelings with genuine empathy
2. Reflects back what they shared to show you truly listened
3. Offers 2-3 practical and personalized coping strategies relevant to what they described
4. Ends with an encouraging, hopeful note

Write 2-3 short paragraphs (8-12 sentences total). Be conversational and caring, like a supportive friend who also understands wellness. {lang_instruction}"""

        user_message = await execute_text_generation(
            user_prompt,
            system_prompt="You are a compassionate, empathetic mental health companion for MedicoScope."
        )
        if not user_message:
            user_message = "Thank you for opening up and sharing how you feel today. Taking time to acknowledge your emotions is an important and brave step. You are not alone, and we are here to support you every step of the way."

        # Doctor-facing clinical report
        doctor_report = None
        urgency = "low"
        if doctor_id:
            doctor_prompt = f"""You are a clinical mental health analyst for MedicoScope MindSpace.
Analyze this patient's mental health check-in transcription and provide a clinical summary for their doctor.

Patient: {patient_name}
Transcription: "{transcript}"

CRITICAL PRIVACY & CONFIDENTIALITY REQUIREMENT:
If the patient mentions any specific third-party persons, family members, friends, colleagues, partners, or any individuals by name:
YOU MUST NEVER INCLUDE THOSE REAL NAMES in this clinical summary or report!
Strictly sanitize and redact all third-party names into generalized non-identifying roles, such as '[Friend]', '[Family Member]', '[Colleague]', '[Partner]', or '[Individual]'.

Provide:
1. Brief clinical summary (2-3 sentences)
2. Key concerns identified
3. Recommended follow-up actions
4. Urgency level: low, moderate, or high

CRITICAL FORMATTING INSTRUCTION:
Do NOT use markdown asterisks (* or **) anywhere in your output. Do not use asterisks for bolding or bullet points.
Use clean capitalized headers like:
CLINICAL SUMMARY:
KEY CONCERNS:
RECOMMENDED ACTIONS:
URGENCY LEVEL:
Use clean bullet points (•) or hyphens (-) for lists. Format as a clean, professional clinical note. Respond in English."""

            raw_doctor_report = await execute_text_generation(
                doctor_prompt,
                system_prompt="You are a clinical mental health analyst for MedicoScope."
            )
            cleaned_body = clean_doctor_report(raw_doctor_report)

            # Determine urgency from keywords
            report_lower = cleaned_body.lower()
            if any(w in report_lower for w in ["high urgency", "urgent", "crisis", "suicidal", "self-harm", "emergency", "critical"]):
                urgency = "high"
            elif any(w in report_lower for w in ["moderate urgency", "moderate", "concerning", "anxiety", "depression"]):
                urgency = "moderate"

            # Resolve location details
            loc_summary = "Location Not Shared / Telehealth"
            if location_label and location_label.strip():
                loc_summary = location_label.strip()
            elif latitude is not None and longitude is not None:
                loc_summary = f"{latitude:.4f}, {longitude:.4f}"
                if maps_url:
                    loc_summary += f" ({maps_url})"

            # Build standardized clinical report with explicit Timestamp and Location
            now_utc = datetime.utcnow().strftime("%b %d, %Y - %I:%M %p UTC")
            now_local = datetime.now().strftime("%I:%M %p")
            voice_marker_text = (
                f"\nVOICE BIOMARKER: {int(voice_marker_score * 100)}% ({voice_marker_headline})"
                if voice_marker_score is not None
                else ""
            )

            structured_report = (
                f"CLINICAL TRIAGE REPORT\n"
                f"PATIENT: {patient_name}\n"
                f"TIMESTAMP: {now_utc} (Local: {now_local})\n"
                f"LOCATION: {loc_summary}\n"
                f"URGENCY LEVEL: {urgency.upper()}"
                f"{voice_marker_text}\n"
                f"----------------------------------------\n"
                f"{cleaned_body}"
            )

            # Scrub third-party names from both the clinical report and doctor-facing transcript
            doctor_report = await anonymize_third_party_names(structured_report, patient_name=patient_name)
            doctor_transcript = await anonymize_third_party_names(transcript, patient_name=patient_name)
            # Final clean pass to eliminate any residual asterisks
            doctor_report = clean_doctor_report(doctor_report)

            # Save notification to Node.js backend (MongoDB).
            try:
                headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
                async with httpx.AsyncClient(timeout=10) as client:
                    await client.post(
                        f"{BACKEND_URL}/mental-health/notifications",
                        headers=headers,
                        json={
                            "doctorId": doctor_id,
                            "patientId": patient_id,
                            "patientName": patient_name,
                            "clinicalReport": doctor_report,
                            "urgency": urgency,
                            "transcript": doctor_transcript,
                            "latitude": latitude,
                            "longitude": longitude,
                            "locationLabel": location_label,
                            "mapsUrl": maps_url,
                            "voiceMarkerScore": voice_marker_score,
                            "voiceMarkerHeadline": voice_marker_headline,
                        },
                    )
            except Exception as notif_err:
                print(f"Warning: Failed to save notification to backend: {notif_err}")

        return {
            "user_message": user_message,
            "transcript": transcript,
            "doctor_report": doctor_report,
            "urgency": urgency,
            "coins_earned": 10,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Rewards ─────────────────────────────────────────────────────────────────

@app.post("/rewards/redeem")
async def redeem_reward(req: RewardRedeemRequest):
    lang_instruction = LANGUAGE_INSTRUCTIONS.get(req.language, LANGUAGE_INSTRUCTIONS["en"])

    # Map Flutter reward types to prompt keys
    type_map = {
        "meditation": "guided_meditation",
        "wellness_report": "weekly_wellness",
        "health_tips": "premium_health_tips",
        "guided_meditation": "guided_meditation",
        "weekly_wellness": "weekly_wellness",
        "premium_health_tips": "premium_health_tips",
    }

    prompts = {
        "guided_meditation": f"""Create a personalized guided meditation script (5-7 minutes).
Include breathing exercises, body scan, and visualization.
Make it calming and suitable for stress relief. {lang_instruction}""",
        "weekly_wellness": f"""Generate a comprehensive weekly wellness report with:
1. Mental health tips for the week
2. Nutrition recommendations
3. Exercise suggestions
4. Sleep hygiene tips
5. Mindfulness exercises
Make it actionable and motivating. {lang_instruction}""",
        "premium_health_tips": f"""Provide 10 premium health tips covering:
1. Physical health
2. Mental well-being
3. Nutrition
4. Sleep quality
5. Stress management
Make each tip detailed and evidence-based. {lang_instruction}""",
    }

    mapped_type = type_map.get(req.reward_type)
    prompt = prompts.get(mapped_type) if mapped_type else None
    if not prompt:
        raise HTTPException(status_code=400, detail="Invalid reward type")

    try:
        content = await execute_text_generation(prompt, system_prompt="You are a health and wellness advisor.")
        if not content:
            content = "Here are your personalized wellness guidelines to help you maintain vibrant health and well-being."
        return {"content": content, "reward_type": req.reward_type}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Vitals Monitoring ───────────────────────────────────────────────────────

VITALS_SCENARIOS = ["resting", "mild_activity", "post_exercise", "sleeping", "stressed"]

# Normal baseline ranges
VITALS_BASELINES = {
    "resting":       {"hr": (65, 80),  "sys": (110, 125), "dia": (70, 80),  "spo2": (96, 99)},
    "mild_activity": {"hr": (80, 100), "sys": (115, 135), "dia": (72, 85),  "spo2": (95, 98)},
    "post_exercise": {"hr": (100,130), "sys": (125, 145), "dia": (75, 88),  "spo2": (94, 98)},
    "sleeping":      {"hr": (55, 70),  "sys": (100, 115), "dia": (60, 75),  "spo2": (95, 99)},
    "stressed":      {"hr": (85, 110), "sys": (125, 145), "dia": (80, 92),  "spo2": (95, 98)},
}

ALERT_THRESHOLDS = {
    "heart_rate_high":  105,
    "heart_rate_low":   60,
    "systolic_high":    132,
    "systolic_low":     90,
    "spo2_low":         94,
}


def _apply_excursion(pt: dict) -> str:
    """Push one vital just past an alert threshold. These are SIMULATED
    excursions (the whole stream is simulated and labelled as such); without
    them most scenarios never breach, so a monitoring session would show no
    alerts at all. Returns the kind of excursion applied."""
    kind = random.choice(["hr_high", "hr_high", "sys_high", "sys_high", "spo2_low", "hr_low"])
    if kind == "hr_high":
        pt["heart_rate"] = round(random.uniform(112, 145), 1)
    elif kind == "sys_high":
        pt["systolic"] = round(random.uniform(138, 168), 1)
        pt["diastolic"] = round(random.uniform(88, 102), 1)
    elif kind == "spo2_low":
        pt["spo2"] = round(random.uniform(86, 92), 1)
    elif kind == "hr_low":
        pt["heart_rate"] = round(random.uniform(46, 56), 1)
    return kind


def _generate_vitals(session: dict) -> list[dict]:
    """Generate 1-3 simulated data points for a tick."""
    scenario = session["scenario"]
    baseline = VITALS_BASELINES[scenario]
    tick = session["tick_counter"]
    points = []

    count = random.randint(1, 3)
    for i in range(count):
        tick += 1
        # Add some drift and noise
        drift = session.get("drift", 0)
        # Occasionally shift drift to simulate natural fluctuation
        if random.random() < 0.08:
            drift = random.uniform(-8, 8)
            session["drift"] = drift

        hr = random.uniform(*baseline["hr"]) + drift + random.gauss(0, 3)
        sys_ = random.uniform(*baseline["sys"]) + drift * 0.5 + random.gauss(0, 4)
        dia = random.uniform(*baseline["dia"]) + drift * 0.3 + random.gauss(0, 2)
        spo2 = random.uniform(*baseline["spo2"]) + random.gauss(0, 0.5)

        # Clamp to physiologically possible values
        hr = max(35, min(200, hr))
        sys_ = max(70, min(220, sys_))
        dia = max(40, min(130, dia))
        spo2 = max(70, min(100, spo2))

        pt = {
            "tick": tick,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "heart_rate": round(hr, 1),
            "systolic": round(sys_, 1),
            "diastolic": round(dia, 1),
            "spo2": round(spo2, 1),
        }

        # Simulated excursions so a session actually surfaces alerts: force one
        # early (so the doctor/patient sees an alert quickly), then ~22% of
        # points thereafter. Most readings still stay in the normal range.
        if tick == 2 or tick == 3 or random.random() < 0.22:
            _apply_excursion(pt)

        points.append(pt)

    session["tick_counter"] = tick
    return points


def _check_alerts(session: dict, points: list[dict]) -> list[dict]:
    """Check data points against thresholds and generate alerts."""
    alerts = []
    for pt in points:
        ts = pt["timestamp"]

        if pt["heart_rate"] > ALERT_THRESHOLDS["heart_rate_high"]:
            alerts.append(_make_alert(session, "tachycardia", "warning",
                f"Heart rate elevated: {pt['heart_rate']} bpm",
                "heart_rate", pt["heart_rate"], ALERT_THRESHOLDS["heart_rate_high"], ts))
        elif pt["heart_rate"] < ALERT_THRESHOLDS["heart_rate_low"]:
            alerts.append(_make_alert(session, "bradycardia", "critical",
                f"Heart rate dangerously low: {pt['heart_rate']} bpm",
                "heart_rate", pt["heart_rate"], ALERT_THRESHOLDS["heart_rate_low"], ts))

        if pt["systolic"] > ALERT_THRESHOLDS["systolic_high"]:
            alerts.append(_make_alert(session, "hypertension", "warning",
                f"Blood pressure high: {pt['systolic']}/{pt['diastolic']} mmHg",
                "systolic", pt["systolic"], ALERT_THRESHOLDS["systolic_high"], ts))
        elif pt["systolic"] < ALERT_THRESHOLDS["systolic_low"]:
            alerts.append(_make_alert(session, "hypotension", "warning",
                f"Blood pressure low: {pt['systolic']}/{pt['diastolic']} mmHg",
                "systolic", pt["systolic"], ALERT_THRESHOLDS["systolic_low"], ts))

        if pt["spo2"] < ALERT_THRESHOLDS["spo2_low"]:
            sev = "critical" if pt["spo2"] < 88 else "warning"
            alerts.append(_make_alert(session, "hypoxia", sev,
                f"SpO2 low: {pt['spo2']}%",
                "spo2", pt["spo2"], ALERT_THRESHOLDS["spo2_low"], ts))

    return alerts


def _make_alert(session: dict, alert_type: str, severity: str,
                message: str, vital: str, current: float, predicted: float,
                timestamp: str) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "type": alert_type,
        "severity": severity,
        "message": message,
        "vital": vital,
        "current_value": current,
        "predicted_value": predicted,
        "timestamp": timestamp,
        "location": session.get("location", ""),
        "latitude": session.get("latitude", 0),
        "longitude": session.get("longitude", 0),
        "maps_url": f"https://www.google.com/maps?q={session.get('latitude',0)},{session.get('longitude',0)}",
        "emergency_contact_name": session.get("emergency_contact_name", ""),
        "emergency_contact_phone": session.get("emergency_contact_phone", ""),
        "patient_id": session.get("patient_id", ""),
        "patient_name": session.get("patient_name", ""),
        "doctor_id": session.get("doctor_id", ""),
        "created_at": datetime.utcnow().isoformat(),
        "read": False,
    }


class VitalsStartRequest(BaseModel):
    patient_id: str
    patient_name: str
    doctor_id: str = ""
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""
    location: str = "Unknown"
    latitude: float = 0.0
    longitude: float = 0.0


class VitalsTickRequest(BaseModel):
    session_id: str


@app.post("/vitals/start")
async def vitals_start(req: VitalsStartRequest):
    session_id = str(uuid.uuid4())
    scenario = random.choice(VITALS_SCENARIOS)

    session = {
        "session_id": session_id,
        "scenario": scenario,
        "patient_id": req.patient_id,
        "patient_name": req.patient_name,
        "doctor_id": req.doctor_id,
        "emergency_contact_name": req.emergency_contact_name,
        "emergency_contact_phone": req.emergency_contact_phone,
        "location": req.location,
        "latitude": req.latitude,
        "longitude": req.longitude,
        "tick_counter": 0,
        "drift": 0,
        "created_at": datetime.utcnow().isoformat(),
    }

    vitals_sessions[session_id] = session

    # Persist the session envelope to MongoDB (durable; survives restarts).
    await _backend_post("/vitals/sessions", {
        "sessionId": session_id,
        "doctorId": req.doctor_id,
        "patientId": req.patient_id,
        "patientName": req.patient_name,
        "location": req.location,
    }, _service_headers())

    return {"session_id": session_id, "scenario": scenario}


@app.post("/vitals/tick")
async def vitals_tick(req: VitalsTickRequest):
    session = vitals_sessions.get(req.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found or expired")

    points = _generate_vitals(session)
    alerts = _check_alerts(session, points)

    # Store alerts per doctor and patient for later querying
    if alerts:
        doctor_id = session.get("doctor_id", "")
        patient_id = session.get("patient_id", "")
        if doctor_id:
            vitals_alerts.setdefault(f"doc_{doctor_id}", []).extend(alerts)
        if patient_id:
            vitals_alerts.setdefault(f"pat_{patient_id}", []).extend(alerts)

        # Persist to MongoDB so the doctor's alert history survives restarts.
        await _backend_post("/vitals/alerts", {
            "doctorId": doctor_id,
            "patientId": patient_id,
            "patientName": session.get("patient_name", ""),
            "sessionId": req.session_id,
            "location": session.get("location", ""),
            "alerts": alerts,
        }, _service_headers())
        await _backend_patch(f"/vitals/sessions/{req.session_id}", {}, _service_headers())

    return {"data_points": points, "alerts": alerts}


@app.delete("/vitals/session/{session_id}")
async def vitals_stop(session_id: str):
    vitals_sessions.pop(session_id, None)
    # Mark the session stopped in MongoDB.
    await _backend_patch(f"/vitals/sessions/{session_id}", {"status": "stopped"}, _service_headers())
    return {"status": "stopped"}


@app.get("/vitals/alerts/doctor/{doctor_id}")
async def vitals_doctor_alerts(doctor_id: str):
    alerts = vitals_alerts.get(f"doc_{doctor_id}", [])
    return {"alerts": alerts}


@app.get("/vitals/alerts/patient/{patient_id}")
async def vitals_patient_alerts(patient_id: str):
    alerts = vitals_alerts.get(f"pat_{patient_id}", [])
    return {"alerts": alerts}


@app.put("/vitals/alerts/{alert_id}/read")
async def vitals_mark_alert_read(alert_id: str):
    # Mark alert as read across all alert lists
    for key in vitals_alerts:
        for alert in vitals_alerts[key]:
            if alert.get("id") == alert_id:
                alert["read"] = True
    return {"status": "ok"}


@app.delete("/vitals/alerts/{alert_id}")
async def vitals_delete_alert(alert_id: str):
    """Delete a vitals alert by ID."""
    for key in list(vitals_alerts.keys()):
        vitals_alerts[key] = [a for a in vitals_alerts[key] if a.get("id") != alert_id]
    return {"status": "deleted"}


# ── Run ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
