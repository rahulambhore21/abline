# TalkCircle: Project Summary & Brief

## Project Overview

*   **What is the app/product?**
    TalkCircle is a production-grade real-time voice communication platform featuring granular speaker tracking, automated session recording, and a comprehensive administrative suite.
*   **Who are the users?**
    The system serves two primary roles: **Hosts** (Admins) who manage sessions and users, and **Participants** (Users) who engage in monitored voice calls.
*   **What core problem does it solve?**
    It provides a verifiable audit trail for voice interactions by tracking exactly who is speaking, for how long, and archiving the actual audio recordings to secure cloud storage for later review or compliance.

## Current Progress

*   **What features are already built?**
    *   ✅ **Real-time Voice**: High-fidelity group voice calls via Agora RTC.
    *   ✅ **Speaker Tracking**: Sub-200ms detection of active speakers with visual indicators.
    *   ✅ **Event Logging**: Automated recording of speaking start/stop times and durations.
    *   ✅ **Session Control**: Remote start/stop of recordings by session hosts.
    *   ✅ **Storage Integration**: Secure multi-part uploads to AWS S3.
    *   ✅ **Admin Dashboard**: Full CRUD for users and a browser for session recordings.
    *   ✅ **Auth System**: JWT-based authentication with role-based access control.
    *   ✅ **Stay Awake**: Screen sleep prevention during active calls.
*   **What is partially built / in progress?**
    *   🏗️ **Stability Refactoring**: Addressing Flutter framework assertion failures during widget unmounting.
    *   🏗️ **Security Polish**: Implementing PIN-protected destructive actions (deletion workflows).
*   **What is not started yet?**
    *   ❌ **Push Notifications**: Real-time alerts for session starts.
    *   ❌ **Rate Limiting**: Protection against API abuse.
    *   ❌ **SSL/Production Hardening**: Full HTTPS and environment-specific security configurations.

## Tech Stack

*   **Frontend**: Flutter (Dart) 3.10+
*   **Backend**: Node.js / Express.js
*   **Database**: MongoDB (Mongoose ODM)
*   **Realtime/Voice Services**: Agora RTC SDK (Voice Engine)
*   **Hosting/Infrastructure**: AWS S3 (Storage), admarktech.cloud (VPS/API)

## Current Architecture

*   **System Workflow**: 
    1.  **Auth**: User logs in -> JWT stored in `shared_preferences`.
    2.  **Token**: Frontend requests Agora Token from Node.js API.
    3.  **RTC**: User joins channel; Agora handles low-latency voice.
    4.  **Tracking**: `SpeakerTracker` class polls Agora volume levels; transitions are debounced locally.
    5.  **Persistence**: Speaking events are POSTed to MongoDB; Audio recordings are streamed to S3 upon session completion.

## Main Challenges / Blockers

*   **Technical Issues**: Handling Flutter's widget lifecycle during rapid state transitions (e.g., `_dependencies.isEmpty` assertion errors).
*   **Architecture Decisions**: Optimizing the frequency of "Speaking Event" API calls to prevent backend saturation while maintaining granular data.

## Requirements / Constraints

*   **Timeline**: Active development / Ready for pre-production testing.
*   **Scalability**: Must support concurrent sessions with 20+ participants each, resulting in high-frequency event logging.
*   **Background Usage Policy**: Strict requirement to prevent the app from running in the background. The app must terminate/reset all active sessions if the user leaves the app or locks their device.
*   **Developer Context**: Focused on building a robust, premium-feeling UI with a stable backend foundation.

## What You Want Help With

*   **Architecture Review**: Validating the stability of the Flutter state management and error handling.
*   **Better Implementation Approach**: Refining the speaker tracking logic to be more resilient to network jitter.
*   **Cost Optimization**: Analyzing Agora and S3 usage to ensure the project remains economically viable at scale.

## Additional Context
The project was recently refactored to modularize the speaker detection logic into a dedicated `SpeakerTracker` service to decouple it from the UI layer.
