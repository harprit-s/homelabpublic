# Microsoft Security OPML Collections

This directory contains curated RSS feed collections for monitoring the Microsoft Security ecosystem. These are optimized for **FreshRSS** but compatible with any standard RSS reader.

## Included Collections
* **c_2 Microsoft Security Products**: Core updates for Sentinel, Defender XDR, Entra, and Security Copilot.
* **c_3 Microsoft Community Blog**: Peer-to-peer insights and engineering deep dives.
* **c_4 Microsoft TI and IR Blogs**: High-fidelity Threat Intelligence and Incident Response updates.

## How to Import into FreshRSS
Follow these steps to add these feeds to your instance:

1. **Download the Files or privide link to repo**: Download the `.opml.xml` files from this repository to your local machine.
2. **Open FreshRSS**: Log in to your FreshRSS instance .
3. **Navigate to Import**:
   - Click the **Subscriptions management** icon (the "+" or list icon) in the top navigation bar.
   - Click **Import / export** at the bottom of the left-hand sidebar.
4. **Upload OPML**:
   - Under the **Import** section, select "List of feeds (OPML format)".
   - Click **Choose File** and select one of the downloaded `.opml.xml` files.
   - Click **Import**.
5. **Configure CSS Selectors (Optional but Recommended)**:
   - For Microsoft Tech Community feeds, go to **Feeds > Manage**.
   - Set the **Article CSS selector** to `.lia-message-body-content` to ensure images load correctly.

---
