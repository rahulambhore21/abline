# TalkCircle: Operational & Maintenance Cost Analysis

## 1. Project Overview
**TalkCircle** is a high-performance real-time voice communication platform featuring granular speaker tracking, session management, and automated audio recording. 

*   **Core Functionality**: Facilitates low-latency voice calls with real-time "who is speaking" indicators and logs every speaking event (start/stop/duration) to a centralized database.
*   **Target Users**: Corporate training teams, monitored communication environments, and organizations requiring audit trails for voice interactions.
*   **Business Purpose**: To provide a managed voice environment where user participation is quantifiable and interactions are archived for quality assurance and compliance.

---

## 2. Tech Stack
The project utilizes a modern, decoupled architecture designed for cross-platform availability and horizontal scalability.

*   **Frontend**: 
    *   **Framework**: Flutter (Dart) 3.10+
    *   **State Management**: ValueNotifier & Custom Controllers
    *   **Key Libraries**: `agora_rtc_engine`, `just_audio`, `http`, `shared_preferences`.
*   **Backend**: 
    *   **Runtime**: Node.js 18+ (LTS)
    *   **Framework**: Express.js
    *   **Middleware**: Helmet (Security), CORS, Compression (Performance), Morgan (Logging).
*   **Database**: 
    *   **Primary**: MongoDB (via Mongoose ODM)
    *   **Schema**: Relational-style documents for Users, Sessions, Speaking Events, and Recordings.
*   **Authentication**: 
    *   **Method**: JWT (JSON Web Tokens)
    *   **Security**: Bcrypt password hashing, Role-Based Access Control (RBAC).
*   **Hosting/Deployment**: 
    *   **API**: Linux-based VPS (Node.js/PM2)
    *   **App**: Android (APK/AAB) & iOS (IPA)
*   **DevOps**: 
    *   **Version Control**: Git
    *   **Scripts**: Custom Node.js scripts for maintenance (e.g., `clear-recordings.js`).

---

## 3. Infrastructure & Services
TalkCircle relies on a mix of managed services and self-hosted components to balance cost and control.

*   **Cloud Provider**: AWS (Amazon Web Services)
*   **Storage (Object)**: AWS S3 (Standard Storage) - Used for persistent storage of `.m4a` and `.mp3` audio recordings.
*   **CDN**: AWS CloudFront (Optional/Recommended for global recording playback).
*   **Database Hosting**: MongoDB Atlas (Managed Service) or Self-hosted MongoDB.
*   **Monitoring/Logging**: 
    *   **Runtime**: Morgan (HTTP request logging).
    *   **Error Tracking**: Global Flutter Error Builder (Frontend), Try-Catch Middleware (Backend).
*   **Backup Systems**: 
    *   **Database**: Daily snapshots via MongoDB Atlas.
    *   **Recordings**: S3 Versioning and Cross-Region Replication (optional).

---

## 4. Third-Party Integrations
*   **Agora RTC**: The core engine for real-time voice. Used for token generation, channel management, and raw volume indication (VAD).
*   **AWS S3 SDK**: Handles multi-part uploads and pre-signed URLs for secure recording access.
*   **Postman/Bruno**: API documentation and testing collections.

---

## 5. Usage Estimates
*Based on a standard implementation for medium-scale usage.*

| Metric | Estimate (Monthly) | Notes |
| :--- | :--- | :--- |
| **Monthly Active Users (MAU)** | 5,000 | Concurrent peaks during sessions. |
| **Concurrent Users** | 200 | Assuming 10 simultaneous 20-person sessions. |
| **Daily API Calls** | 50,000+ | High volume due to granular speaking event tracking. |
| **Storage Growth** | 500 GB | ~30MB per hour per user of recorded audio. |
| **Data Transfer (Out)** | 1.5 TB | Agora voice traffic + S3 recording downloads. |

---

## 6. Feature Breakdown
*   **Real-time Functionality**: Sub-200ms voice latency via Agora; live speaker UI updates via 200ms volume polling.
*   **Scheduled Jobs**: 
    *   Recording cleanup (Automated via Node.js script).
    *   Session expiration (Automated via DB TTL indices).
*   **Admin Dashboard**: 
    *   User creation/deletion with PIN protection.
    *   Global recording browser and playback.
    *   Real-time session monitoring.
*   **File Management**: Secure upload of session recordings directly to S3 with metadata syncing to MongoDB.

---

## 7. Security & Compliance
*   **Authentication**: Stateless JWT with 24h expiration.
*   **Authorization**: Two-tier RBAC (`host` and `user`). Hosts have destructive permissions (delete user/recording).
*   **Data Encryption**: 
    *   **In-Transit**: Mandatory HTTPS/TLS 1.2+.
    *   **At-Rest**: S3-managed server-side encryption (AES-256).
*   **Backup/DR**: MongoDB multi-node replica sets ensuring 99.9% data availability.

---

## 8. Maintenance Requirements
*   **Routine Tasks**: 
    *   S3 bucket lifecycle policy audits (moving old recordings to Glacier/Deletion).
    *   MongoDB index optimization for the `speaking_events` collection (which grows the fastest).
*   **Update Management**: 
    *   Monthly `npm audit` and `flutter pub upgrade` cycles.
    *   Agora SDK version parity checks.
*   **Support Expectations**: 
    *   Tier 1: User management and password resets.
    *   Tier 2: Agora connection troubleshooting and S3 permission fixes.

---

## 9. Deployment Details
*   **Environments**: 
    *   `Development`: Local Node.js server + Flutter Emulator.
    *   `Staging`: `admarktech.cloud` staging subdomain.
    *   `Production`: Dedicated high-availability VPS.
*   **Regions**: Primary deployment in AWS `ap-south-1` (Mumbai) or `us-east-1` (N. Virginia) based on user proximity.
*   **Scaling**: 
    *   **Vertical**: Increase VPS RAM for Node.js event handling.
    *   **Horizontal**: Agora scales automatically; MongoDB requires sharding if events exceed 100M records.
