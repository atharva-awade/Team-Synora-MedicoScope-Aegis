class ApiConstants {
  static const String baseUrl = 'https://medicoscope-api-lbto.onrender.com/api';

  // Chatbot - the redeployed service that has the Aegis consult route.
  static const String chatbotBaseUrl =
      'https://medicoscope-chatbot-lbto.onrender.com';

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';

  // Users
  static const String profile = '/users/profile';

  // Doctors
  static const String doctorPatients = '/doctors/patients';

  // Patients
  static const String patientLink = '/patients/link';
  static const String patientRecords = '/patients/records';
  static const String patientDoctor = '/patients/doctor';

  // Detections
  static const String detections = '/detections';

  // Mental Health
  static const String mentalHealthAnalyze = '/mental-health/analyze';
  static const String mentalHealthNotifications =
      '/mental-health/notifications';

  // Rewards
  static const String rewardsRedeem = '/rewards/redeem';

  // CardioScope (Heart Sound Analysis)
  static const String cardioBaseUrl = 'https://cardio-l3eb.onrender.com';
  static const String cardioPredict = '/predict';

  // Vitals Monitoring (Python chatbot server)
  static const String vitalsStart = '/vitals/start';
  static const String vitalsTick = '/vitals/tick';
  static const String vitalsDoctorAlerts = '/vitals/alerts/doctor';
  static const String vitalsPatientAlerts = '/vitals/alerts/patient';
  static const String vitalsSession = '/vitals/session';

  // Vitals Summaries (Node.js server - persisted)
  static const String vitalsSummary = '/vitals/summary';
  static const String vitalsSummaries = '/vitals/summaries';

  // Medical Summary (for chatbot context)
  static const String patientMedicalSummary = '/patients/medical-summary';

  // Chat History
  static const String chatMessage = '/chat/message';
  static const String chatHistory = '/chat/history';
  static const String chatSession = '/chat/session';

  // MindSpace History
  static const String mindspaceSession = '/mindspace/session';
  static const String mindspaceHistory = '/mindspace/history';
  static const String mindspaceDoctor = '/mindspace/doctor';

  // Rewards (DB-synced)
  static const String rewards = '/rewards';

  // Claimed Rewards
  static const String claimedRewards = '/claimed-rewards';

  // Admin
  static const String adminPatients = '/admin/patients';
  static const String adminDoctors = '/admin/doctors';
  static const String adminStats = '/admin/stats';
  static const String adminNearbyDoctors = '/admin/nearby-doctors';

  // Nearby Doctors (patient search)
  static const String nearbyDoctorsSearch = '/nearby-doctors/search';
  static const String nearbyDoctorsSpecializations = '/nearby-doctors/specializations';

  // ── Aegis Quality Gate (server-side engine is the single source of truth) ──
  // The rules live in server/quality/packs/*.json and are executed only by
  // server/quality/lib/engine.js. The app calls these endpoints; it does not
  // re-implement the rules, because two implementations of a quality rule are
  // two definitions of quality.
  static const String qualityGatePacks = '/quality-gate/packs';
  static const String qualityGateEvaluate = '/quality-gate/evaluate';
  static const String qualityGateCertify = '/quality-gate/certify';
  static const String qualityGateFinalize = '/quality-gate/finalize';
  static const String qualityGateVerify = '/quality-gate/verify';
  static const String qualityGateCertificate = '/quality-gate/certificate';
  static const String qualityGateRewriteCheck = '/quality-gate/rewrite/check';
  static const String qualityGateCritiqueCompile = '/quality-gate/critique/compile';
}
