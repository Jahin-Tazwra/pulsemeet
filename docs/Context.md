# PulseMeet App Documentation

## Overview

PulseMeet is a mobile app allowing users to spontaneously create and join short, time-boxed meetups ("pulses") within a dynamic radius. Each pulse generates an ephemeral chat group that auto-deletes after the event. The app emphasizes a modern, minimalist, and intuitive UI/UX.

---

## User Flow

### Onboarding

* Phone number or social media login (Google, Apple)
* Optional selfie verification for trust-building
* Clear and guided permission prompts for location

### Main Screen

* **Map View:** Clean, minimalistic map displaying live pulses as intuitive pins.
* **List View:** Easily scrollable cards displaying pulses by proximity and time left.
* **Pulse Card Info:**

  * Activity icon/title (emoji-based)
  * Host’s name (first name, last initial)
  * Distance from user
  * Pulse countdown
  * Remaining spots visually indicated

### Creating a Pulse

1. Tap **“Create Pulse”** (prominent FAB - floating action button).
2. Select or type:

   * Activity (emoji-centric, simplified selector)
   * Duration (easy slider or quick-tap buttons: 15, 30, 45, 60 min)
   * Participants limit (user-friendly numeric selector)
3. Post pulse (quick confirmation animation).

### Joining a Pulse

1. Tap on a visually appealing pulse card.
2. Press **“Join”** (one-tap action).
3. Enter a clear, uncluttered ephemeral chat screen.
4. Quick reply shortcuts and intuitive map navigation.

### Pulse Chat

* Modern chat bubbles with real-time typing indicators.
* Animated countdown timer bar.
* Smooth transition to read-only state after pulse.
* Graceful fade-out and auto-delete animation post-event.

### Post-Pulse Feedback

* Simple, visually appealing thumbs-up/down interaction.
* Instant visual acknowledgment of feedback.

---

## Features

### Core Features (MVP)

* Rapid pulse creation
* Adaptive pulse radius
* Real-time ephemeral chat
* Safety and moderation toolkit (simple UI)
* Automatic data expiry and deletion

### Advanced Features (Future)

* "Ghost Mode" for privacy
* Pulse+ subscription (premium filters, larger groups, remote joins)
* Business Boost feature for promotions
* Integrated payments (ticket purchases, splits)
* Campus-specific pulse networks
* AI-suggested meetup spots
* Voice assistant integration and widgets
* Smart notifications and alerts

---

## Safety & Moderation

* Mandatory verification (clear step-by-step)
* Optional live selfie verification
* Intuitive block/report buttons
* Transparent toggle for location sharing
* Prompt moderation workflows
* Feedback loop via ratings to ensure trust

---

## Technical Architecture

### Front-end

* Flutter framework (responsive, cross-platform)
* Google Maps SDK for interactive mapping
* Efficient geolocation with geofencing

### Back-end

* Platform: Supabase (serverless, real-time backend)
* Database: PostgreSQL with PostGIS for spatial queries
* Authentication: Supabase Auth (social login and phone verification)
* Real-time messaging and notifications: Supabase real-time
* Temporary storage and cleanup: Supabase storage and functions
* Cloud functions: Supabase serverless functions for dynamic features

### Security & Privacy

* Strictly temporary data handling
* Secure and limited exposure of user locations

---

## Monetization

* **Pulse+ Premium Subscription:**

  * Unlock enhanced features and customizations
  * Advanced filtering and group capabilities

* **Business Boosts:**

  * Promote pulses to wider audiences
  * Simple purchase via credits

* **Event Partnerships:**

  * Featured event listings

---

---

## Potential Risks & Mitigation

| Risk                   | Mitigation Strategy                                |
| ---------------------- | -------------------------------------------------- |
| Low initial engagement | Seed with ambassadors, strategic business partners |
| Safety concerns        | Robust verification and rapid moderation response  |
| Battery usage concerns | Geolocation optimization and smart geofencing      |

---

## Next Steps for Development

1. Prototype testing with modern Figma designs.
2. Flutter app development:

   * Prioritize pulse creation and map view.
3. Supabase backend implementation:

   * Efficient ephemeral chat and geospatial queries.
4. Pilot testing in targeted locations for feedback and refinement.

---

This structured documentation provides a clear and practical guide for developers to design, implement, and iterate PulseMeet, prioritizing modern UI/UX principles and leveraging Supabase as the backend solution.
