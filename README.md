# Finance Tracker

Cross-platform (Android + Windows) personal finance app built with Flutter.

## Features

- UPI SMS Capture — Auto-parse UPI SMS from PhonePe, GPay, Paytm, etc.
- Manual Entry — Add transactions manually on any device
- Real-time Sync — Powered by Supabase Realtime
- Dashboard — Summary cards (Earned/Spent/Saved/Net) + category pie chart + trend chart
- Smart Categorization — Rule-based + Claude LLM fallback
- Goals — Set savings goals with live progress tracking
- Invoice Sidebar — Track freelance invoices with 3 columns: Invoiced (USD), Received in PayPal, Received in Bank
- Finance Agent — Claude-powered Q&A: "Can I afford X?", "What did I waste money on?"

## Tech Stack

| Layer | Tech |
|---|---|
| Frontend | Flutter (Dart) |
| Backend / DB | Supabase (Postgres, Realtime) |
| State | Riverpod |
| Charts | fl_chart |
| LLM | Anthropic Claude API |
| SMS Parsing | Regex engine |

## Setup

### Prerequisites

- Flutter SDK (stable)
- Supabase account (free tier)
- Anthropic API key

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com)
2. Run the migration in `supabase/migrations/00001_init.sql` in the SQL editor
3. Copy your project URL and anon key

### 2. Configure

Edit `lib/core/constants.dart`:

```dart
static const String supabaseUrl = 'https://your-project.supabase.co';
static const String supabaseAnonKey = 'your-anon-key';
static const String claudeApiKey = 'sk-ant-your-claude-key';
```

### 3. Run

```bash
flutter pub get
flutter run
```

## Project Structure

```
lib/
├── main.dart                  # Entry point
├── app.dart                   # App shell with bottom nav + invoice drawer
├── core/                      # Theme, Supabase client, constants
├── models/                    # Transaction, Goal, Invoice, CategoryRule
├── providers/                 # Riverpod state management
├── features/
│   ├── transactions/          # Transaction list + add form
│   ├── dashboard/             # Summary cards + pie chart
│   ├── goals/                 # Goal list + progress + allocate
│   ├── invoices/              # Slide-in sidebar drawer
│   ├── agent/                 # Chat UI + Claude integration
│   └── sms/                   # SMS parser + listener
└── widgets/                   # Shared UI components
```

## Build

```bash
# Android
flutter build appbundle

# Windows
flutter build windows
```
