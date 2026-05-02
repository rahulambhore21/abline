# TalkCircle: Real-Time Voice & Speaker Analytics

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-18+-339933?logo=node.js)](https://nodejs.org)
[![MongoDB](https://img.shields.io/badge/MongoDB-Atlas-47A248?logo=mongodb)](https://www.mongodb.com)
[![AWS](https://img.shields.io/badge/AWS-S3-232F3E?logo=amazon-aws)](https://aws.amazon.com)

TalkCircle is a production-ready real-time voice communication platform built with Flutter and Node.js. It features advanced speaker detection, automated session recording, and a comprehensive admin suite for user and recording management.

---

## 📖 Table of Contents
1. [Project Overview](#1-project-overview)
2. [Tech Stack](#2-tech-stack)
3. [Infrastructure & Services](#3-infrastructure--services)
4. [Third-Party Integrations](#4-third-party-integrations)
5. [Usage Estimates](#5-usage-estimates)
6. [Feature Breakdown](#6-feature-breakdown)
7. [Security & Compliance](#7-security--compliance)
8. [Maintenance Requirements](#8-maintenance-requirements)
9. [Deployment Details](#9-deployment-details)
10. [Developer Quick Start](#10-developer-quick-start)

---

## 1. Project Overview
*   **What it does**: Enables low-latency group voice calls with real-time speaker identification and duration tracking.
*   **Target Users**: Organizations requiring high-fidelity voice logs, training centers, and remote teams.
*   **Core Business Purpose**: Providing a verifiable audit trail of voice participation and archived recordings for quality control.

---

## 2. Tech Stack
*   **Frontend**: Flutter (Dart) for Android and iOS.
*   **Backend**: Node.js with Express.js (REST API).
*   **Database**: MongoDB (Mongoose ODM) for session and event persistence.
*   **Authentication**: JWT (JSON Web Tokens) with Role-Based Access Control (RBAC).
*   **Hosting**: AWS Infrastructure for storage and high-availability VPS for API services.

---

## 3. Infrastructure & Services
*   **Cloud Provider**: AWS (Amazon Web Services).
*   **Storage**: AWS S3 for hosting high-quality audio recordings (`.m4a`/`.mp3`).
*   **Monitoring**: Morgan-based HTTP logging and custom error-handling middleware.
*   **Backup**: MongoDB Atlas automated snapshots; S3 bucket versioning.

---

## 4. Third-Party Integrations
*   **Agora RTC**: Powering real-time voice channels and voice activity detection (VAD).
*   **AWS S3 SDK**: Secure file transfer and storage management.
*   **Postman**: For API lifecycle management and testing.

---

## 5. Usage Estimates
| Metric | Monthly Estimate |
| :--- | :--- |
| **Active Users** | 5,000 |
| **Concurrent Sessions** | 200 |
| **Storage Consumption** | ~500 GB |
| **Data Bandwidth** | ~1.5 TB |

---

## 6. Feature Breakdown
*   **Real-time Speaker Detection**: 200ms polling for sub-second visual feedback on active speakers.
*   **Session Management**: Full lifecycle control (Start/Stop/Record) by authorized hosts.
*   **Admin Dashboard**: Native Flutter interface for user management, recording audits, and session status.
*   **Automatic Archiving**: Speaking events are logged instantly; recordings are synced to S3 upon session completion.
*   **Background Usage Prevention**: The app automatically disconnects from calls and resets when moved to the background or the screen is locked to ensure privacy and resource efficiency.
*   **Screen Sleep Prevention**: The display is kept awake automatically during active voice calls to prevent session interruption.

---

## 7. Security & Compliance
*   **Authentication**: Stateless JWT with 24-hour TTL.
*   **Data Integrity**: AES-256 encryption at rest (S3) and TLS 1.2+ in transit.
*   **Access Control**: Secure PIN verification for destructive admin actions (user/recording deletion).
*   **Anti-Background Monitoring**: Active lifecycle enforcement to prevent unauthorized background audio activity.

---

## 8. Maintenance Requirements
*   **Database**: Regular indexing of `speaking_events` to maintain query performance.
*   **Storage**: Automated cleanup of temporary recordings and migration of old logs to cold storage.
*   **Dependencies**: Periodic `flutter pub upgrade` and `npm audit fix` for security patches.

---

## 9. Deployment Details
*   **Environments**: Dev (Local), Staging (Cloud), Production (High-Availability VPS).
*   **Regions**: Global availability via AWS regions (defaulting to Mumbai/N. Virginia).
*   **Scaling**: Horizontally scalable Node.js clusters and Agora-managed RTC infrastructure.

---

## 10. Developer Quick Start

### Backend Setup
1. `cd backend`
2. `npm install`
3. Configure `.env` with Agora and AWS credentials.
4. `npm start`

### App Setup
1. `cd app`
2. `flutter pub get`
3. `flutter run --dart-define=BACKEND_URL=https://your-api.com`

---

*For detailed cost analysis and operational workflows, see [OPERATIONAL_README.md](./OPERATIONAL_README.md).*
