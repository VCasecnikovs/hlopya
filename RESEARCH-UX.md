# Meeting Recording / Note-Taking Tools - UI/UX Research

**Date:** 2026-02-18
**Tools analyzed:** Granola, Otter.ai, Fireflies.ai, tl;dv, Fathom

---

## Table of Contents

1. [Granola](#1-granola)
2. [Otter.ai](#2-otterai)
3. [Fireflies.ai](#3-firefliesai)
4. [tl;dv](#4-tldv)
5. [Fathom](#5-fathom)
6. [Comparative Matrix](#6-comparative-matrix)
7. [Key UX Patterns & Takeaways](#7-key-ux-patterns--takeaways)

---

## 1. Granola

**Platform:** macOS, Windows, iOS (no web, no Android)
**Approach:** Local audio capture (no bot), hybrid human+AI note-taking
**Website:** [granola.ai](https://granola.ai)

### Main Window Layout

- **Split-screen editor** resembling Apple Notes or Google Docs - intentionally familiar, zero learning curve
- **Left sidebar** with navigation:
  - Home / recent notes (meeting list)
  - Folders (organize by project, client, meeting type)
  - Trash folder (restore or permanently delete notes)
  - **People view** (person icon, bottom-left of sidebar) - auto-populated searchable list of meeting attendees
  - **Companies view** (building icon, bottom-left of sidebar) - auto-populated company directory from calendar events
  - Team views for shared notes
- **Main content area:** Clean notepad canvas for the active note
- **Right panel / sidebar chat:** AI chat that knows context of the current meeting and related meetings

### Before Recording (Pre-Meeting)

- Calendar integration surfaces upcoming meetings auto-populated from Google Calendar or Outlook
- Pop-up notification appears 1 minute before scheduled meetings (2+ attendees) offering to start transcription
- Settings > "Coming Up" shows which calendar events will be transcribed
- You can select a meeting template before the meeting starts (29 built-in templates: customer discovery, user interviews, 1-on-1s, project kick-offs, pipeline reviews, etc.)
- Custom templates can be created; "Auto" template for general use

### During Recording (Recording State)

- **Menu bar icon** - Granola sits in macOS menu bar, captures system audio silently (no bot joins calls)
- **Floating recording indicator ("nub")** - appears on the right-hand side of screen during active transcription
  - Shows **green dancing bars** at the bottom indicating audio is being captured
  - Click to jump back to your meeting note
  - Draggable - can be repositioned anywhere on screen
  - Small and unobtrusive by design
- **Notepad remains active** - you type notes as you normally would during the meeting
  - Clean blank canvas, minimal formatting options
  - Quick bullets, no formal structure required
  - You can press the back button to glance at previous notes while Granola continues transcribing
  - **Escape key** returns to homescreen even while transcribing
- **Live transcript** available in a small box (clicking the little moving circle tab at the bottom)
  - Transcript displayed without speaker names (criticized - looks like "SMS between two unnamed parties")
  - No scroll bar for quick navigation in transcript

### After Recording (Post-Meeting)

- AI processes conversation and generates structured notes:
  - Key decisions
  - Action items with assignees
  - Unresolved questions
  - Emphasized quotes with hyperlinks to exact transcript timestamps
- **Visual distinction:** User notes appear in **black text**, AI-generated content in **gray text**
- AI adds hierarchy and structure to make notes scannable
- Notes formatted in **Notion-style page** with editable text fields
- Notes broken into categories separated by bullet points
- Click any AI-generated line to verify against the source transcript timestamp
- Template selection available post-meeting to reformat (e.g., hiring meeting, weekly standup)
- **"Ask Granola" prompts:** Buttons for "Write a follow up email", "List action items", "What's their budget?" etc.
- One-click sharing: public links, Slack, email, CRM, Notion, ATS

### Meeting List & Organization

- Home view shows list of recent meetings
- Multi-select meetings, then "Ask Granola" or "Add to folder" for batch operations
- Search across all meetings, people, companies
- Search bar in People and Companies view for contact discovery
- Meetings auto-grouped by calendar event, people, and companies

### Settings & Preferences

- Dark mode toggle (released late 2025, toggle fixed Jan 2026)
- Calendar connection settings (Google, Outlook, SSO)
- Template management (29 built-in + custom)
- Internal Jargon feature - add custom vocabulary for better transcription
- Integration settings: Notion, Slack, Attio, Zapier
- Account deletion with confirmation step

### Visual Design / Color Scheme

- **Light mode:** Clean, minimalist, white/light gray backgrounds. Criticized by some as "gray on gray" / "Windows 95" bland
- **Dark mode:** Available since late 2025, with ongoing styling fixes for chips, avatars, toggle switches
- Native platform feel (macOS/Windows) - not a web wrapper
- No web version - purely native apps

### Unique UX Patterns

- **"Invisible AI" philosophy** - the app augments your notes rather than replacing them; zero-friction
- **No bot presence** - captures audio directly from device, other participants never know
- **Hybrid note-taking** - only tool that blends manual user notes with AI transcription, creating a collaborative document
- **People & Companies CRM-lite** - auto-builds a contact database from calendar events with enrichment (profile pictures, job titles, company info)
- **70% weekly retention** - attributed to the invisible, friction-free design
- **@mentions** - tag teammates in notes with email notification
- **Plain text paste** (Cmd+Shift+V) for clean formatting

---

## 2. Otter.ai

**Platform:** Web, macOS, Windows, iOS, Android
**Approach:** Bot-based recording OR bot-free (desktop app), real-time transcription
**Website:** [otter.ai](https://otter.ai)

### Main Window Layout

- **Left navigation panel:**
  - Home (recent conversations/dashboard)
  - My Conversations
  - All Conversations
  - Shared with Me
  - Folders
  - Apps section
- **Center content area:** Conversation list or active conversation view
- **Right panel:** Calendar sync, upload options, start recording button
- Dashboard is the control room: clean list of transcripts with quick actions to record, upload, or reopen conversations
- Recent items float to the top

### Before Recording

- Calendar integration pulls upcoming meetings
- Can start recording from: web app, desktop app, Chrome extension, or mobile
- Meeting reminders available on desktop app
- Options to use bot-based recording (OtterPilot joins meeting) or bot-free recording (desktop app captures system audio)

### During Recording (Recording State)

- **Desktop app recording indicator:** Small overlay widget that appears above all applications when you navigate away from Otter during live recording
  - Draggable - can be positioned anywhere on screen
  - Controls: Finish recording, Pause, Resume, Open Otter
- **Otter Live Notes:** Real-time transcript appears as the meeting progresses
- **Red LIVE transcription indicator** at the top of Zoom meetings (for hosted meetings)
- Can wear headphones during recording with desktop app (bot-free mode)
- **Chrome extension** provides in-browser recording panel for Google Meet

### After Recording (Conversation Page)

- **Two-tab layout:**
  - **Summary tab:** AI-generated summary, action items, outline (all auto-generated)
  - **Transcript tab:** Full transcript with speaker labels, timestamps, playback controls
- **Right-side panel** (context-dependent):
  - Otter Chat (AI Q&A about the conversation)
  - AI-generated Outline
  - Comment threads
- **Speaker identification:**
  - Speakers labeled as "Speaker 1", "Speaker 2" etc. initially
  - Green check mark appears next to manually tagged/confirmed speakers
  - Speaker participation breakdown shown as percentage for each speaker
- **Transcript interaction:**
  - Add reactions (emojis)
  - Insert images
  - Add highlights (color-coded)
  - Add comments
  - Edit transcript text directly
  - Export: TXT, DOCX, PDF, SRT (subtitles)
- **Keywords** displayed for quick scanning
- **Block Transcript Display** option available for different viewing modes

### Meeting List & Organization

- My Conversations / All Conversations tabs
- Each item shows: meeting title, duration, participants, short transcript preview
- Action items and highlights captured by AI shown in preview
- Folder organization
- Channel system for organizing conversations
- Search across conversations

### Settings & Preferences

- Meeting type templates (customizable)
- Auto-join settings for meetings
- Speaker identification training
- Integration settings
- Recording preferences (bot vs bot-free)
- Export customization (speaker names, timestamps, highlights, branding)

### Visual Design / Color Scheme

- **Dark blue and white** primary color scheme
- Mobile apps and web interface share consistent visual language
- Supports **dark mode** (toggle in settings)
- Modern color palette: green, blue, yellow, red semantic colors (OKLCH color space)
- Clean but can feel **cluttered** after account creation due to many customization options on dashboard
- Some users note the interface can feel **"a little dated"**

### Unique UX Patterns

- **Dual recording modes** - bot-based (OtterPilot) OR bot-free (desktop app system audio)
- **Live Notes** - real-time transcription visible during meeting, sharable with others
- **Speaker participation analytics** - percentage breakdown of talk time per speaker
- **Otter Chat** - AI Q&A interface on right panel, can scope queries to specific channels/conversations/folders
- **Emoji reactions** on transcript segments
- **465+ unique UI screens** in their design system (very feature-rich/complex)
- **Custom meeting type templates** for different conversation types

---

## 3. Fireflies.ai

**Platform:** Web, macOS, Windows (desktop app launched Nov 2025), Chrome extension, mobile
**Approach:** Bot-based recording + desktop app system audio, AI meeting intelligence
**Website:** [fireflies.ai](https://fireflies.ai)

### Main Window Layout

- **Left navigation bar:**
  - My Feed (overview of all meetings at a glance)
  - Meetings / Notebook (meeting list)
  - Channels
  - Integrations
  - Settings
- **Center content:** Meeting notebook (active meeting details) or meeting list
- **Meeting notebook page** (per meeting):
  - Left column: AI summary
  - Right area: Transcript, recording, analytics
  - Tabs/sections for Smart Search, Index, Soundbites, Comments

### Before Recording

- Calendar integration with Google Calendar
- Bot (Fred) auto-joins scheduled meetings
- Desktop app can start recording manually
- Pre-meeting insights panel shows prospect information and company context before calls

### During Recording (Recording State)

- **Fireflies bot ("Fred")** joins the meeting as a participant
- **Live Assist** (launched Nov 2025) - floating panel on desktop showing:
  - Live notes (written in real-time)
  - Live transcripts
  - Instant summaries
  - Action items
  - "Ask Fred" - mid-call AI Q&A without leaving the meeting
- **Desktop app** provides quick access from system tray
  - Start/stop recordings
  - Use Live Assist during live meetings
  - Review past conversations
  - Stays available in background
- Works across browser, desktop app, Chrome extension, mobile

### After Recording (Meeting Notebook / "Notepad")

- **AI Summary section** (left column):
  - Keywords - quick scan of relevant terms
  - Meeting Overview - short paragraph
  - Time-stamped Notes - bullet points grouped into chapters
  - Action Items - auto-assigned to speakers
  - Customizable summary formats ("Super Summaries")
  - Can expand, regenerate, or customize any section
- **Transcript section:**
  - Full automated transcription with speaker labels and timestamps
  - Hover over text to hear audio of that specific line
  - Click timestamps to jump to recording point
  - Smart Search with AI Filters
- **Video/Audio recording** playback
- **Analytics:**
  - Speaking time per participant
  - Sentiment analysis
  - Talk-time breakdowns
  - Topic detection
  - Conversation intelligence metrics
- **Soundbites** - shareable audio/video clips
- **Comments** - timestamped notes and annotations
- **Index** - jump to action items or AI summary sections

### Meeting List & Organization

- "My Feed" provides overview of all meetings
- Notebook view lists all meetings (yours + team members')
- Meeting Info modal for quick details
- Smart Search across all transcripts
- Filter by date, participants, topics

### Settings & Preferences

- Integration settings (Salesforce, Asana, Slack, HubSpot, etc.)
- Bot behavior settings
- Summary customization
- Notification preferences
- Team management

### Visual Design / Color Scheme

- **Clean, minimalist design** with straightforward navigation
- Clear icons and labels for key functionalities
- **Dark-themed** interface elements (especially Live Assist panel)
- Well-chosen colors to highlight important details while fading less crucial ones
- Some criticism: **"somewhat cluttered"** compared to competitors
- No explicit dark mode toggle found - appears to use a standard light theme with some dark elements
- Color contrast reported as occasionally problematic

### Unique UX Patterns

- **Live Assist floating panel** - real-time AI assistance during meetings without switching apps
- **"Ask Fred"** - mid-meeting AI queries (unique named AI assistant)
- **Pre-meeting intelligence** - prospect/company info shown before calls start
- **Super Summaries** - customizable, expandable AI summary sections
- **Conversation intelligence analytics** - sentiment, talk-time, topic detection (sales-team oriented)
- **Soundbites** - shareable audio/video clips from meetings
- **100+ language support** for transcription
- **Most feature-rich** of all tools analyzed - also means most complex UI

---

## 4. tl;dv

**Platform:** Web (primary), Chrome extension, mobile ("tl;dv Mobile Lite")
**Approach:** Bot-based recording, video + transcript + clips
**Website:** [tldv.io](https://tldv.io)

### Main Window Layout

- **Left sidebar (side panel):**
  - Meetings & Folders
  - AI Reports
  - Clips & Reels
  - Settings
- **Center content:** Meeting library / active meeting details
- **Meeting library** is the hub - searchable collection of all recordings across platforms (Zoom, Google Meet, MS Teams)

### Before Recording

- Calendar integration for auto-joining meetings
- Chrome extension provides recording button next to Google Meet controls
- Configure auto-sharing settings before meeting starts

### During Recording (Recording State)

- **tl;dv bot** joins the meeting as a participant
- **Chrome extension panel** (for Google Meet) with three controls:
  - Stop and save recording
  - Change auto-sharing settings
  - Collapse interface (let AI work in background)
- **In-meeting note-taking** - type notes in tl;dv interface during the call
  - Notes become timestamped bookmarks
  - Can retrace agenda and jump to specific moments later
- No native desktop app - operates through web + Chrome extension

### After Recording (Meeting Page)

- **Video recording** with playback
- **Speaker-labeled transcript** tied directly to video
  - Automatic speaker recognition and labeling
  - Can rename speakers after the meeting
  - Every voice identified and attributed
  - Search transcripts by keyword, jump to moments
- **AI Summary:**
  - Key discussion points
  - Action items
  - Decisions made
  - Next steps
- **Highlight system:**
  - Highlight any part of transcript to auto-generate a video snippet/clip
  - Combine multiple clips into **"Reels"** - shareable compilations
- **Clips & Reels** section for managing snippets
- No native transcript editing capability (noted limitation)

### Meeting List & Organization

- Searchable library of all meetings across platforms
- Shared folders for team collaboration
- Search across transcripts, titles, and participants by keyword
- Jump to specific moments from search results
- Multi-meeting summaries - ask AI questions across multiple meetings
- Date-based organization

### Settings & Preferences

- Meeting templates for different conversation types
- Auto-join/auto-record settings
- Sharing preferences
- Integration settings (CRM, Slack, etc.)
- Language settings (30+ languages)

### Visual Design / Color Scheme

- **Purple-accented branding** (primary brand color)
- Web-based interface - no native desktop app feel
- Criticized for being **"a mess"** with:
  - Persistent visual bugs
  - Cluttered upgrade prompts
  - Inconsistent spacing
  - Interface feels **"bloated"** and **"occasionally clunky"**
  - Transcript highlighting hard to follow
- **Learning curve** noted - "not immediately intuitive"
- No explicit dark mode mentioned
- "Multi-meeting conversational intelligence dashboard" referenced but layout not well-documented

### Unique UX Patterns

- **Clips & Reels** - create video snippets from transcript highlights, combine into shareable compilations (strongest clip-making UX of all tools)
- **Multi-meeting AI** - ask questions across your entire meeting library, not just one meeting
- **Timestamp-based note-taking** - notes taken during meeting become navigational bookmarks
- **Video-first** - unlike Granola (audio-only), tl;dv emphasizes video recording and video clip sharing
- **Global search** across all platforms (Zoom + Meet + Teams unified)
- Most suited for **customer research and sales enablement** workflows

---

## 5. Fathom

**Platform:** Desktop app (macOS, Windows), Chrome extension, web dashboard
**Approach:** Bot-based recording (joins as participant), real-time highlights
**Website:** [fathom.video](https://fathom.video)

### Main Window Layout

- **Clean, distraction-free dashboard** - every summary is one click away
- **Meeting list** with calendar-synced events
  - Meetings pulled from Zoom, Google Meet, Microsoft Teams calendar links
  - Chronological organization
- **Call view** (individual meeting page):
  - Call recording (video playback)
  - Action items section
  - Bookmarks
  - Highlights
  - Full transcript
  - Timestamps for navigation
- Searchable repository / knowledge base across all meetings
- **Taskbar integration** - app icon lives in system tray, not requiring constant window presence

### Before Recording

- Calendar events auto-populate on Fathom dashboard
- Auto-join: Fathom automatically joins as attendee when meeting begins
- Can also manually start with green "Start Recording" button
- Auto-record toggle in settings for all future meetings
- **Recording Notification Banner** - customizable image shown to attendees indicating Fathom is recording

### During Recording (Recording State)

- **Fathom bot** joins the meeting as a visible participant
- **Live panel** (Zoom: right side of Zoom window):
  - Command center for capturing key moments
  - **Highlight button** - click to flag important moments during the call
    - Quick note field for context
    - Categories: crucial decisions, key points, objections, questions, action items
    - Highlights auto-summarized, timestamped, inserted into post-meeting notes
  - **Bookmark button** - create timestamp markers for later reference
  - Start/Stop recording controls
  - Pause/Resume
- **Google Meet integration** - Fathom appears as a button in the Meet interface (not floating pop-up)
- **Floating window notification** - small indicator when bot joins the call
- Desktop app provides fuller experience than Zoom app (custom highlights, action items, bookmarks)

### After Recording (Call View)

- **Instant summary** delivered immediately after meeting ends
  - Structured formal format
  - Attendees list
  - Action items section
  - Questions highlighted with speaker attribution
  - No tone customization (noted limitation - "no obvious way to set how you want the summary to sound")
- **Full transcript:**
  - Chat-style format with speaker identification
  - Click any sentence to jump to that point in video
  - **Editable** - reassign speakers, clean up wording, trim filler
  - Searchable with context-aware results grouped by speaker
  - **Color-coded progress bar** and embedded transcript links
- **Highlights** flagged in transcript for quick scanning
- **Bookmarks** as navigation timestamps
- **"Ask Fathom"** - natural language queries across past meetings
- Template selection for reformatting summaries (14 templates, Premium/Team)

### Meeting List & Organization

- Dashboard lists all recorded meetings chronologically
- Each entry: title, date, participants, summary preview
- Search across team recordings (global search)
- Meetings organized by date
- Tag and highlight system for categorization
- **Instant video playback** from search results

### Settings & Preferences

- Bot name customization (name shown when joining meetings)
- Default meeting template selection for external meetings
- Auto-generate action items toggle
- Auto-record toggle
- Recording notification banner customization
- Integration settings (CRM, Slack, etc.)
- Summary template customization (tone, detail, format - 14 types) - Premium/Team only
- Company logo customization
- **No dark mode** (frequently requested but not yet available as of early 2026)

### Visual Design / Color Scheme

- Described as **"slightly emo, mostly beige"** - muted, warm tones
- Space-themed branding (astronauts, cosmic elements)
- Clean, minimalist interface - "distraction-free"
- **Light mode only** (no dark mode as of 2026)
- Orange-pink, pink-purple, yellow-purple gradient accents on marketing/landing pages
- In-app interface is more subdued
- Can feel **cluttered** with tooltips and clickable options appearing on mouse hover
- Bars and pop-ups during meetings noted as potentially obtrusive

### Unique UX Patterns

- **Real-time highlight capture** - strongest "moment marking" UX of all tools; one-click highlights with categories during live meetings
- **Free forever** individual plan with unlimited recordings/summaries (strongest free tier)
- **Editable transcripts** - reassign speakers, clean up wording, trim sections
- **Color-coded progress bar** in transcript view
- **"Ask Fathom"** - cross-meeting AI search with natural language
- **Recording notification banner** - customizable image telling attendees about recording
- **Bot name customization** - personalize the recorder's display name
- **Distraction-free philosophy** but paradoxically has many tooltips/popups

---

## 6. Comparative Matrix

| Feature | Granola | Otter.ai | Fireflies.ai | tl;dv | Fathom |
|---|---|---|---|---|---|
| **Recording method** | System audio (no bot) | Bot OR system audio | Bot + desktop audio | Bot | Bot |
| **Native desktop app** | Yes (Mac, Win) | Yes (Mac, Win) | Yes (Mac, Win, Nov 2025) | No (web + extension) | Yes (Mac, Win) |
| **Mobile app** | iOS | iOS, Android | iOS, Android | "Mobile Lite" | No |
| **Web app** | No | Yes | Yes | Yes (primary) | Yes (dashboard) |
| **Dark mode** | Yes (late 2025) | Yes | Partial/unclear | No | No |
| **Live transcript** | Yes (small box) | Yes (Live Notes) | Yes (Live Assist) | No (notes only) | No (highlights only) |
| **Speaker labels in transcript** | No | Yes | Yes | Yes | Yes |
| **Editable transcript** | No | Yes | Limited | No | Yes |
| **Video recording** | No (audio only) | Yes | Yes | Yes | Yes |
| **AI chat / Q&A** | Yes (sidebar) | Yes (Otter Chat) | Yes (Ask Fred) | Yes (multi-meeting) | Yes (Ask Fathom) |
| **Real-time highlights** | No | No | No | Timestamp notes | Yes (strongest) |
| **Clips / Reels** | No | No | Soundbites | Yes (strongest) | Bookmarks |
| **CRM-like features** | People & Companies | No | Analytics | No | No |
| **Templates** | 29 built-in + custom | Custom types | Customizable | Templates | 14 types |
| **Floating indicator** | Green bars nub | Draggable widget | Live Assist panel | Extension panel | Live panel (Zoom) |
| **Free tier** | Limited | Limited | Limited | Generous free | Unlimited free (individual) |

---

## 7. Key UX Patterns & Takeaways

### Recording Initiation

- **Automatic (calendar-triggered):** Granola, Otter, Fireflies, Fathom all auto-start from calendar events
- **Manual start button:** All tools offer manual recording start as fallback
- **Best UX:** Granola's 1-minute-before notification pop-up - asks permission just in time without requiring you to think about it in advance

### Floating / Mini Recording Indicator

- **Granola:** Smallest, most minimal - small "nub" with green dancing bars on right side, draggable
- **Otter:** Small draggable overlay with recording controls (pause/stop/resume/open)
- **Fireflies:** Largest - full floating panel with live notes, transcript, action items, AI Q&A
- **tl;dv:** Chrome extension panel embedded in Google Meet (not floating)
- **Fathom:** Live panel docked to right side of Zoom window with highlight/bookmark buttons
- **Pattern:** Spectrum from minimal (Granola) to feature-rich (Fireflies Live Assist)

### Transcript Display Patterns

- **Speaker identification:** Otter, Fireflies, tl;dv, Fathom all use speaker labels. Granola notably does NOT show speaker names
- **Timestamp linking:** Universal - all tools link transcript to audio/video timestamps
- **Chat-style format:** Fathom uses chat-bubble style per speaker. Others use labeled blocks
- **Editability:** Otter and Fathom allow full transcript editing. Others are read-only
- **Color coding:** Fathom uses color-coded progress bar. Otter uses highlight colors. Others minimal color

### Notes / Summary Display

- **Granola:** Unique hybrid - user notes (black) + AI notes (gray) interleaved, Notion-style editable page
- **Otter:** Two-tab approach - Summary tab (overview) and Transcript tab (detail)
- **Fireflies:** Multi-section: Keywords + Overview + Timestamped Notes + Action Items
- **tl;dv:** AI summary with key points, action items, decisions, next steps
- **Fathom:** Formal structured summary with attendees, action items, questions, highlights
- **Pattern:** All use structured sections with action items; Granola is unique in blending user + AI content

### Session / Meeting Organization

- **List view:** All tools use chronological meeting lists as primary organization
- **Folders:** Granola, Otter, tl;dv support folder organization
- **People/Company grouping:** Granola unique with auto-built People & Companies directories
- **Global search:** All tools support full-text search across meetings
- **Multi-meeting AI:** tl;dv and Fathom strongest for cross-meeting queries

### Standout Design Decisions

1. **Granola's "Invisible AI"** - No bot, no video, no visible AI during meeting. Just a tiny indicator. Achieved 70% weekly retention. Lesson: less is more
2. **Fireflies' Live Assist** - Opposite approach - maximum real-time intelligence during meeting. Floating panel with live notes, transcript, AI answers. For power users who want everything
3. **Fathom's real-time highlights** - One-click moment capture during live meetings is the strongest "capture now, process later" pattern
4. **tl;dv's Clips & Reels** - Best post-meeting content creation: highlight transcript -> auto-generate video clip -> combine into reels. Optimized for sharing/stakeholder communication
5. **Otter's dual recording mode** - Only tool offering both bot-based and bot-free recording from the same platform, letting users choose based on context

### Design Philosophy Spectrum

```
Minimal / Invisible -------- Feature-Rich / Visible
  Granola  ---  Fathom  ---  Otter  ---  tl;dv  ---  Fireflies
```

- **Granola:** "AI should be invisible" - augment, don't replace
- **Fathom:** "Capture moments as they happen" - real-time highlights
- **Otter:** "Full collaboration platform" - comments, reactions, sharing
- **tl;dv:** "Turn meetings into content" - clips, reels, sharing
- **Fireflies:** "AI teammate" - maximum intelligence, analytics, automation

### Common Criticisms Across All Tools

1. **Interface clutter** - Otter, Fireflies, Fathom, tl;dv all criticized for some degree of UI clutter
2. **Bot awkwardness** - Otter, Fireflies, tl;dv, Fathom all have visible bots (Granola avoids this entirely)
3. **Limited customization** - Most tools lack deep theme/color/layout customization
4. **Dark mode gaps** - Only Granola and Otter fully support dark mode. Fathom and tl;dv do not
5. **Transcript accuracy with multiple speakers** - Universal challenge across all tools

### Recommendations for New Tool Design

Based on this research, the highest-impact UX decisions for a new meeting tool would be:

1. **Bot-free recording** (Granola approach) - significantly reduces social friction
2. **Minimal during-meeting UI** - small draggable indicator, not a full panel
3. **Dark mode from day one** - table stakes in 2026
4. **Speaker-labeled transcripts** (unlike Granola) - essential for review
5. **Hybrid note-taking** (Granola's killer feature) - let users type + AI enhance
6. **Real-time highlights** (Fathom's strength) - one-click moment capture
7. **Clean post-meeting view** - structured summary + full transcript (Otter's two-tab approach)
8. **People/Company auto-CRM** (Granola's innovation) - meeting context builds over time
9. **Clip creation** (tl;dv's strength) - easy sharing of specific moments
10. **Native app feel** - avoid web-wrapper aesthetic, match platform conventions

---

## Sources

- [Granola official site](https://granola.ai)
- [Granola updates / changelog](https://www.granola.ai/updates)
- [Granola People and Companies docs](https://docs.granola.ai/help-center/people-and-companies)
- [Granola review (Zack Proser)](https://zackproser.com/blog/granola-ai-review)
- [Granola review (tl;dv)](https://tldv.io/blog/granola-review/)
- [Granola: The AI Note-Taker with Big Plans (Anthony Tan)](https://overtheanthill.substack.com/p/granola)
- [The Art of Invisible AI (UX Planet)](https://uxplanet.org/the-art-of-invisible-ai-what-granolas-70-retention-teaches-us-about-product-design-2de5a2836d17)
- [Otter.ai official site](https://otter.ai)
- [Otter Desktop App announcement](https://otter.ai/blog/introducing-the-otter-desktop-app)
- [Otter Conversation Page Overview](https://help.otter.ai/hc/en-us/articles/5093228433687-Conversation-Page-Overview)
- [Otter Speaker Identification](https://help.otter.ai/hc/en-us/articles/21665587209367-Speaker-Identification-Overview)
- [Otter Desktop App Help](https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows)
- [Otter UI screens (Nicelydone)](https://nicelydone.club/apps/otter)
- [Otter review (Notta)](https://www.notta.ai/en/blog/otter-ai-review)
- [Fireflies.ai official site](https://fireflies.ai)
- [Fireflies Desktop App](https://fireflies.ai/desktop)
- [Fireflies Live Assist](https://fireflies.ai/live-assist)
- [Fireflies AI Meeting Summaries guide](https://guide.fireflies.ai/articles/9547055509-Fireflies-AI-Meeting-Summaries)
- [Fireflies Notepad guide](https://guide.fireflies.ai/articles/6653885315-learn-about-the-fireflies-notepad)
- [Fireflies review (ScreenApp)](https://screenapp.io/blog/fireflies-review)
- [Fireflies review (Votars)](https://votars.ai/en/blog/fireflies-review-2025/)
- [tl;dv official site](https://tldv.io)
- [tl;dv Recordings & Transcriptions](https://tldv.io/features/meeting-recordings-transcriptions/)
- [tl;dv Google Meet extension](https://tldv.io/recording-google-meet/)
- [tl;dv review (Hyprnote)](https://char.com/blog/tldv-review/)
- [tl;dv honest review](https://tldv.io/blog/tldv-honest-review/)
- [tl;dv review (Jamie)](https://www.meetjamie.ai/blog/tldv-review)
- [Fathom official site](https://fathom.video)
- [Fathom overview](https://www.fathom.ai/overview)
- [Fathom Quick Start Guide](https://fathom.video/quick-start)
- [Fathom Settings Help](https://help.fathom.video/en/articles/3239617)
- [Fathom review (Unite.AI)](https://www.unite.ai/fathom-review/)
- [Fathom review (BlueDot)](https://www.bluedothq.com/blog/fathom-review)
- [Fathom review (tl;dv)](https://tldv.io/blog/honest-review-of-fathom/)
- [Otter vs Fireflies vs Fathom comparison (Index.dev)](https://www.index.dev/blog/otter-vs-fireflies-vs-fathom-ai-meeting-notes-comparison)
