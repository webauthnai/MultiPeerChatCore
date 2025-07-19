// Copyright 2025 FIDO3.ai
// Generated on: 25-7-19

import Foundation

// MARK: - WebAdminContent namespace
public enum WebAdminContent {
    
    // MARK: - Admin HTML Content
    public static func generateAdminIndexHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>🛡️ Admin Panel</title>
            <link rel="stylesheet" href="/admin/admin.css">
        </head>
        <body>
            <div class="admin-container">
                <header class="admin-header">
                    <h1>🛡️ Admin Panel</h1>
                    <div class="admin-actions">
                        <button id="refresh-btn" onclick="refreshUsers()">🔄</button>
                        <button id="back-to-chat-btn" onclick="goBackToChat()">💬</button>
                    </div>
                </header>

                <div class="stats-section">
                    <div class="stat-card">
                        <h3>Total</h3>
                        <span id="total-users">0</span>
                    </div>
                    <div class="stat-card">
                        <h3>Active</h3>
                        <span id="active-users">0</span>
                    </div>
                    <div class="stat-card">
                        <h3>Disabled</h3>
                        <span id="disabled-users">0</span>
                    </div>
                </div>

                <div class="controls-section">
                    <div class="bulk-actions">
                        <h3>Bulk Actions</h3>
                        <div class="bulk-controls">
                            <input type="text" id="ip-address-input" placeholder="IP address">
                            <button onclick="disableByIP()">Disable IP</button>
                        </div>
                    </div>

                    <div class="filters">
                        <h3>Filters</h3>
                        <div class="filter-controls">
                            <select id="status-filter" onchange="filterUsers()">
                                <option value="all">All Users</option>
                                <option value="enabled">Enabled</option>
                                <option value="disabled">Disabled</option>
                            </select>
                            <input type="text" id="search-input" placeholder="Search username..." onkeyup="filterUsers()">
                        </div>
                    </div>
                </div>

                <div class="users-section">
                    <div class="users-header">
                        <h3>Users (<span id="user-count">0</span>)</h3>
                    </div>

                    <div class="users-table-container">
                        <table id="users-table">
                            <thead>
                                <tr>
                                    <th>#</th>
                                    <th>Username</th>
                                    <th>Emoji</th>
                                    <th>Status</th>
                                    <th>Created</th>
                                    <th>Last Login</th>
                                    <th>IP</th>
                                    <th>Signs</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody id="users-tbody">
                                <tr><td colspan="9" class="loading">Loading users...</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- User Details Modal -->
                <div id="user-details-modal" class="modal hidden">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h3>User Details</h3>
                            <button class="close-btn" onclick="closeUserDetailsModal()">&times;</button>
                        </div>
                        <div class="modal-body">
                            <div class="user-detail-grid">
                                <div class="detail-item">
                                    <label>User ID</label>
                                    <span id="detail-id"></span>
                                </div>
                                <div class="detail-item">
                                    <label>User #</label>
                                    <span id="detail-user-number"></span>
                                </div>
                                <div class="detail-item">
                                    <label>Username</label>
                                    <span id="detail-username"></span>
                                </div>
                                <div class="detail-item">
                                    <label>Emoji</label>
                                    <div class="emoji-edit-container">
                                        <span id="detail-emoji" class="emoji-display"></span>
                                        <button id="edit-emoji-btn" class="edit-emoji-btn" onclick="openEmojiEditor()">Edit</button>
                                    </div>
                                </div>
                                <div class="detail-item">
                                    <label>Status</label>
                                    <span id="detail-status"></span>
                                </div>
                                <div class="detail-item">
                                    <label>Admin Role</label>
                                    <div class="admin-toggle-container">
                                        <span id="detail-is-admin"></span>
                                        <button id="toggle-admin-btn" class="toggle-admin-btn" onclick="toggleAdminRole()">Toggle</button>
                                    </div>
                                </div>
                                <div class="detail-item">
                                    <label>Created</label>
                                    <span id="detail-created"></span>
                                </div>
                                <div class="detail-item">
                                    <label>Last Login</label>
                                    <span id="detail-last-login"></span>
                                </div>
                                <div class="detail-item">
                                    <label>IP Address</label>
                                    <span id="detail-ip"></span>
                                </div>
                                <div class="detail-item">
                                    <label>Sign Count</label>
                                    <span id="detail-sign-count"></span>
                                </div>
                                <div class="detail-item full-width">
                                    <label>Credential ID</label>
                                    <span id="detail-credential-id" class="credential-text"></span>
                                </div>
                                <div class="detail-item full-width">
                                    <label>Public Key</label>
                                    <textarea id="detail-public-key" class="public-key-text" readonly></textarea>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Emoji Editor Modal -->
                <div id="emoji-editor-modal" class="modal hidden">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h3>Edit User Emoji</h3>
                            <button class="close-btn" onclick="closeEmojiEditor()">&times;</button>
                        </div>
                        <div class="modal-body">
                            <div class="emoji-picker-grid">
                                <span class="emoji-option" onclick="selectEmoji('👤')">👤</span>
                                <span class="emoji-option" onclick="selectEmoji('🐶')">🐶</span>
                                <span class="emoji-option" onclick="selectEmoji('🐱')">🐱</span>
                                <span class="emoji-option" onclick="selectEmoji('🐭')">🐭</span>
                                <span class="emoji-option" onclick="selectEmoji('🐹')">🐹</span>
                                <span class="emoji-option" onclick="selectEmoji('🐰')">🐰</span>
                                <span class="emoji-option" onclick="selectEmoji('🦊')">🦊</span>
                                <span class="emoji-option" onclick="selectEmoji('🐻')">🐻</span>
                                <span class="emoji-option" onclick="selectEmoji('🐼')">🐼</span>
                                <span class="emoji-option" onclick="selectEmoji('🐨')">🐨</span>
                                <span class="emoji-option" onclick="selectEmoji('🐯')">🐯</span>
                                <span class="emoji-option" onclick="selectEmoji('🦁')">🦁</span>
                                <span class="emoji-option" onclick="selectEmoji('🐸')">🐸</span>
                                <span class="emoji-option" onclick="selectEmoji('🐵')">🐵</span>
                                <span class="emoji-option" onclick="selectEmoji('🙈')">🙈</span>
                                <span class="emoji-option" onclick="selectEmoji('🙉')">🙉</span>
                                <span class="emoji-option" onclick="selectEmoji('🙊')">🙊</span>
                                <span class="emoji-option" onclick="selectEmoji('🐒')">🐒</span>
                                <span class="emoji-option" onclick="selectEmoji('🦍')">🦍</span>
                                <span class="emoji-option" onclick="selectEmoji('🦧')">🦧</span>
                                <span class="emoji-option" onclick="selectEmoji('🐕')">🐕</span>
                                <span class="emoji-option" onclick="selectEmoji('🐩')">🐩</span>
                                <span class="emoji-option" onclick="selectEmoji('🐺')">🐺</span>
                                <span class="emoji-option" onclick="selectEmoji('🦝')">🦝</span>
                                <span class="emoji-option" onclick="selectEmoji('🐈')">🐈</span>
                                <span class="emoji-option" onclick="selectEmoji('🐅')">🐅</span>
                                <span class="emoji-option" onclick="selectEmoji('🐆')">🐆</span>
                                <span class="emoji-option" onclick="selectEmoji('🦓')">🦓</span>
                                <span class="emoji-option" onclick="selectEmoji('🦄')">🦄</span>
                                <span class="emoji-option" onclick="selectEmoji('🐴')">🐴</span>
                                <span class="emoji-option" onclick="selectEmoji('🐎')">🐎</span>
                                <span class="emoji-option" onclick="selectEmoji('🦌')">🦌</span>
                                <span class="emoji-option" onclick="selectEmoji('🐮')">🐮</span>
                                <span class="emoji-option" onclick="selectEmoji('🐂')">🐂</span>
                                <span class="emoji-option" onclick="selectEmoji('🐃')">🐃</span>
                                <span class="emoji-option" onclick="selectEmoji('🐄')">🐄</span>
                                <span class="emoji-option" onclick="selectEmoji('🐷')">🐷</span>
                                <span class="emoji-option" onclick="selectEmoji('🐖')">🐖</span>
                                <span class="emoji-option" onclick="selectEmoji('🐗')">🐗</span>
                                <span class="emoji-option" onclick="selectEmoji('🐽')">🐽</span>
                                <span class="emoji-option" onclick="selectEmoji('🐏')">🐏</span>
                                <span class="emoji-option" onclick="selectEmoji('🐑')">🐑</span>
                                <span class="emoji-option" onclick="selectEmoji('🐐')">🐐</span>
                                <span class="emoji-option" onclick="selectEmoji('🐪')">🐪</span>
                                <span class="emoji-option" onclick="selectEmoji('🐫')">🐫</span>
                                <span class="emoji-option" onclick="selectEmoji('🦒')">🦒</span>
                                <span class="emoji-option" onclick="selectEmoji('🐘')">🐘</span>
                                <span class="emoji-option" onclick="selectEmoji('🦏')">🦏</span>
                                <span class="emoji-option" onclick="selectEmoji('🦛')">🦛</span>
                                <span class="emoji-option" onclick="selectEmoji('🐊')">🐊</span>
                                <span class="emoji-option" onclick="selectEmoji('🐢')">🐢</span>
                                <span class="emoji-option" onclick="selectEmoji('🦎')">🦎</span>
                                <span class="emoji-option" onclick="selectEmoji('🐍')">🐍</span>
                                <span class="emoji-option" onclick="selectEmoji('🐲')">🐲</span>
                                <span class="emoji-option" onclick="selectEmoji('🐉')">🐉</span>
                                <span class="emoji-option" onclick="selectEmoji('🦕')">🦕</span>
                                <span class="emoji-option" onclick="selectEmoji('🦖')">🦖</span>
                            </div>
                            <div class="emoji-editor-actions">
                                <button id="save-emoji-btn" onclick="saveEmojiChange()" disabled>Save</button>
                                <button onclick="closeEmojiEditor()">Cancel</button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <script src="/admin/admin.js"></script>
        </body>
        </html>
        """
    }

    // MARK: - Admin CSS Content
    public static func generateAdminCSS() -> String {
        return """
        /* Professional Admin Panel CSS - Using Chat App Color Scheme */
        :root {
            /* Use same color scheme as main chat app */
            --bg-primary: #eceff1;
            --bg-secondary: #ffffff;
            --text-primary: #2d3748;
            --text-secondary: #4a5568;
            --accent-color: #007AFF;
            --accent-color-hover: #0056CC;
            --border-color: #e2e8f0;
            --status-connected: #34C759;
            --status-disconnected: #FF3B30;
            --modal-bg: rgba(255, 255, 255, 0.95);
            --gradient-start: #667eea;
            --gradient-end: #764ba2;
            --input-bg: #ffffff;
            --input-text: #2d3748;
            --disabled-bg: #8E8E93;
            --orange-color: #FF9500;
            --red-color: #FF3B30;
            --green-color: #34C759;
            --admin-shadow: 0 2px 10px rgba(0, 0, 0, 0.08);
            --admin-shadow-lg: 0 10px 25px rgba(0, 0, 0, 0.15);
            
            /* Safari scrollbar appearance - light mode */
            color-scheme: light;
        }

        /* Dark Mode */
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #121212;
                --bg-secondary: #1e1e1e;
                --text-primary: #e2e8f0;
                --text-secondary: #cbd5e0;
                --accent-color: #007AFF;
                --accent-color-hover: #0056CC;
                --border-color: #2d3748;
                --status-connected: #30D158;
                --status-disconnected: #FF453A;
                --modal-bg: rgba(30, 30, 30, 0.95);
                --gradient-start: #4a5568;
                --gradient-end: #2d3748;
                --input-bg: #2d3748;
                --input-text: #e2e8f0;
                --disabled-bg: #636366;
                --orange-color: #FF9F0A;
                --red-color: #FF453A;
                --green-color: #30D158;
                --admin-shadow: 0 2px 10px rgba(0, 0, 0, 0.25);
                --admin-shadow-lg: 0 10px 25px rgba(0, 0, 0, 0.4);
                
                /* Safari scrollbar appearance - dark mode */
                color-scheme: dark;
            }
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            transition: background-color 0.2s ease, color 0.2s ease, border-color 0.2s ease;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, var(--gradient-start) 0%, var(--gradient-end) 100%), var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.5;
            min-height: 100vh;
            font-size: 14px;
        }

        .admin-container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 12px;
            min-height: 100vh;
        }

        /* Header - Condensed */
        .admin-header {
            background: var(--modal-bg);
            backdrop-filter: blur(10px);
            border-radius: 8px;
            padding: 16px 20px;
            margin-bottom: 16px;
            box-shadow: var(--admin-shadow);
            display: flex;
            justify-content: space-between;
            align-items: center;
            border: 1px solid var(--border-color);
        }

        .admin-header h1 {
            font-size: 20px;
            font-weight: 600;
            color: var(--accent-color);
            margin: 0;
        }

        .admin-actions {
            display: flex;
            gap: 8px;
        }

        .admin-actions button {
            padding: 8px 16px;
            border: none;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s ease;
            min-height: 36px;
        }

        #refresh-btn {
            background: var(--accent-color);
            color: white;
        }

        #refresh-btn:hover {
            background: var(--accent-color-hover);
        }

        #back-to-chat-btn {
            background: var(--text-secondary);
            color: white;
        }

        #back-to-chat-btn:hover {
            background: var(--text-primary);
        }

        /* Stats Section - Condensed Grid */
        .stats-section {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 12px;
            margin-bottom: 16px;
        }

        .stat-card {
            background: var(--modal-bg);
            backdrop-filter: blur(10px);
            border-radius: 8px;
            padding: 16px 12px;
            text-align: center;
            box-shadow: var(--admin-shadow);
            border: 1px solid var(--border-color);
        }

        .stat-card h3 {
            font-size: 11px;
            font-weight: 500;
            color: var(--text-secondary);
            margin-bottom: 6px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .stat-card span {
            font-size: 24px;
            font-weight: 700;
            color: var(--accent-color);
            display: block;
        }

        /* Controls Section - More Compact */
        .controls-section {
            background: var(--modal-bg);
            backdrop-filter: blur(10px);
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 16px;
            box-shadow: var(--admin-shadow);
            border: 1px solid var(--border-color);
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }

        .bulk-actions,
        .filters {
            margin-bottom: 0;
            display: flex;
            flex-direction: column;
        }

        .bulk-actions:last-child,
        .filters:last-child {
            margin-bottom: 0;
        }

        .bulk-actions h3,
        .filters h3 {
            font-size: 14px;
            font-weight: 600;
            margin-bottom: 10px;
            color: var(--text-primary);
        }

        .bulk-controls,
        .filter-controls {
            display: flex;
            gap: 8px;
            align-items: stretch;
        }

        .bulk-controls input,
        .filter-controls input,
        .filter-controls select {
            flex: 1;
            padding: 8px 12px;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            background: var(--input-bg);
            color: var(--input-text);
            font-size: 13px;
            min-height: 36px;
        }

        .bulk-controls input:focus,
        .filter-controls input:focus,
        .filter-controls select:focus {
            outline: none;
            border-color: var(--accent-color);
            box-shadow: 0 0 0 2px rgba(0, 122, 255, 0.1);
        }

        .bulk-controls button {
            padding: 8px 12px;
            background: var(--red-color);
            color: white;
            border: none;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: background 0.2s ease;
            white-space: nowrap;
            min-height: 36px;
        }

        .bulk-controls button:hover {
            background: #D70015;
        }

        .filters {
            display: flex;
            flex-direction: column;
        }

        .filter-controls {
            display: flex;
            gap: 8px;
            align-items: stretch;
        }



        /* Users Section - Professional Table */
        .users-section {
            background: var(--modal-bg);
            backdrop-filter: blur(10px);
            border-radius: 8px;
            padding: 16px;
            box-shadow: var(--admin-shadow);
            border: 1px solid var(--border-color);
        }

        .users-header {
            margin-bottom: 12px;
        }

        .users-header h3 {
            font-size: 16px;
            font-weight: 600;
            color: var(--text-primary);
        }

        /* Professional Table Design */
        .users-table-container {
            overflow-x: auto;
            border-radius: 6px;
            border: 1px solid var(--border-color);
            background: var(--bg-secondary);
        }

        #users-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }

        #users-table th {
            background: var(--bg-primary);
            padding: 10px 8px;
            text-align: left;
            font-weight: 600;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: var(--text-secondary);
            border-bottom: 1px solid var(--border-color);
            white-space: nowrap;
        }

        #users-table td {
            padding: 10px 8px;
            border-bottom: 1px solid var(--border-color);
            vertical-align: middle;
        }

        #users-table tr:last-child td {
            border-bottom: none;
        }

        #users-table tr:hover {
            background: var(--bg-primary);
        }

        /* Status Badges - Using App Colors */
        .status-badge {
            padding: 3px 8px;
            border-radius: 12px;
            font-size: 10px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            display: inline-block;
        }

        .status-enabled {
            background: rgba(52, 199, 89, 0.15);
            color: var(--green-color);
            border: 1px solid rgba(52, 199, 89, 0.3);
        }

        .status-disabled {
            background: rgba(255, 59, 48, 0.15);
            color: var(--red-color);
            border: 1px solid rgba(255, 59, 48, 0.3);
        }

        @media (prefers-color-scheme: dark) {
            .status-enabled {
                background: rgba(48, 209, 88, 0.2);
                color: var(--green-color);
            }

            .status-disabled {
                background: rgba(255, 69, 58, 0.2);
                color: var(--red-color);
            }
        }

        /* Action Buttons - Compact */
        .action-buttons {
            display: flex;
            gap: 4px;
            align-items: center;
        }

        .action-btn {
            padding: 4px 8px;
            border: none;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s ease;
            min-height: 28px;
        }

        .btn-view {
            background: var(--accent-color);
            color: white;
        }

        .btn-view:hover {
            background: var(--accent-color-hover);
        }

        .btn-delete {
            background: var(--red-color);
            color: white;
        }

        .btn-delete:hover {
            background: #D70015;
        }

        /* Compact Toggle Switch */
        .toggle-switch {
            position: relative;
            display: inline-block;
            width: 40px;
            height: 20px;
        }

        .toggle-switch input {
            opacity: 0;
            width: 0;
            height: 0;
        }

        .slider {
            position: absolute;
            cursor: pointer;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: var(--disabled-bg);
            transition: 0.3s;
            border-radius: 20px;
        }

        .slider:before {
            position: absolute;
            content: "";
            height: 14px;
            width: 14px;
            left: 3px;
            bottom: 3px;
            background-color: white;
            transition: 0.3s;
            border-radius: 50%;
            box-shadow: 0 1px 3px rgba(0,0,0,0.3);
        }

        input:checked + .slider {
            background-color: var(--green-color);
        }

        input:checked + .slider:before {
            transform: translateX(20px);
        }

        /* Professional Modal */
        .modal {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.6);
            display: flex;
            justify-content: center;
            align-items: center;
            z-index: 1000;
            padding: 20px;
        }

        .modal.hidden {
            display: none;
        }

        .modal-content {
            background: var(--modal-bg);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            width: 100%;
            max-width: 600px;
            max-height: 90vh;
            overflow-y: auto;
            box-shadow: var(--admin-shadow-lg);
            border: 1px solid var(--border-color);
        }

        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 16px 20px;
            border-bottom: 1px solid var(--border-color);
            background: var(--bg-primary);
            border-radius: 12px 12px 0 0;
        }

        .modal-header h3 {
            font-size: 16px;
            font-weight: 600;
            color: var(--text-primary);
        }

        .close-btn {
            background: none;
            border: none;
            font-size: 20px;
            cursor: pointer;
            color: var(--text-secondary);
            width: 32px;
            height: 32px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 6px;
            transition: background 0.2s ease;
        }

        .close-btn:hover {
            background: var(--border-color);
        }

        .modal-body {
            padding: 20px;
        }

        .user-detail-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }

        .detail-item {
            display: flex;
            flex-direction: column;
            gap: 4px;
        }

        .detail-item.full-width {
            grid-column: 1 / -1;
        }

        .detail-item label {
            font-size: 10px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: var(--text-secondary);
        }

        .detail-item span {
            font-size: 13px;
            color: var(--text-primary);
            word-break: break-all;
            padding: 6px;
            background: var(--bg-primary);
            border-radius: 4px;
            border: 1px solid var(--border-color);
        }

        .credential-text {
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
            font-size: 10px !important;
        }

        .public-key-text {
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
            font-size: 10px;
            background: var(--bg-primary);
            border: 1px solid var(--border-color);
            border-radius: 4px;
            padding: 8px;
            resize: vertical;
            min-height: 80px;
            color: var(--text-primary);
            width: 100%;
        }

        .public-key-text:focus {
            outline: none;
            border-color: var(--accent-color);
            box-shadow: 0 0 0 2px rgba(0, 122, 255, 0.1);
        }

        /* Mobile Responsive */
        @media (max-width: 768px) {
            .admin-container {
                padding: 8px;
            }

            .admin-header {
                padding: 12px 16px;
                flex-direction: column;
                gap: 12px;
                text-align: center;
            }

            .admin-header h1 {
                font-size: 18px;
            }

            .admin-actions {
                width: 100%;
                justify-content: center;
            }

            .stats-section {
                grid-template-columns: repeat(3, 1fr);
                gap: 8px;
            }

            .stat-card {
                padding: 12px 8px;
            }

            .stat-card span {
                font-size: 20px;
            }

            .controls-section {
                padding: 12px;
            }

            .bulk-controls {
                flex-direction: column;
                gap: 8px;
            }

            .filters {
                flex-direction: column;
                gap: 8px;
            }

            .users-section {
                padding: 12px;
            }

            #users-table {
                font-size: 11px;
            }

            #users-table th,
            #users-table td {
                padding: 6px 4px;
            }

            .action-buttons {
                flex-direction: column;
                gap: 2px;
            }

            .action-btn {
                font-size: 10px;
                padding: 3px 6px;
            }

            .toggle-switch {
                width: 32px;
                height: 16px;
            }

            .slider:before {
                height: 10px;
                width: 10px;
                left: 3px;
                bottom: 3px;
            }

            input:checked + .slider:before {
                transform: translateX(16px);
            }

            .user-detail-grid {
                grid-template-columns: 1fr;
            }

            .modal-content {
                margin: 10px;
            }

            .modal-header,
            .modal-body {
                padding: 12px 16px;
            }
        }

        /* Extra Small Mobile */
        @media (max-width: 480px) {
            .stats-section {
                grid-template-columns: 1fr 1fr;
            }

            .stat-card h3 {
                font-size: 10px;
            }

            .stat-card span {
                font-size: 18px;
            }

            #users-table th,
            #users-table td {
                padding: 4px 2px;
            }

            .action-btn {
                font-size: 9px;
                padding: 2px 4px;
                min-height: 24px;
            }
        }

        /* Loading States */
        .loading {
            text-align: center;
            padding: 20px;
            color: var(--text-secondary);
            font-style: italic;
        }

        /* Admin Login Page Styles */
        .login-container {
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, var(--gradient-start) 0%, var(--gradient-end) 100%), var(--bg-primary);
            padding: 20px;
        }

        .login-card {
            background: var(--modal-bg);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            padding: 32px;
            width: 100%;
            max-width: 400px;
            box-shadow: var(--admin-shadow-lg);
            border: 1px solid var(--border-color);
        }

        .login-header {
            text-align: center;
            margin-bottom: 24px;
        }

        .login-header h1 {
            font-size: 24px;
            font-weight: 600;
            color: var(--accent-color);
            margin-bottom: 6px;
        }

        .login-header p {
            color: var(--text-secondary);
            font-size: 13px;
        }

        .login-form {
            margin-bottom: 24px;
        }

        .form-group {
            margin-bottom: 16px;
        }

        .form-group label {
            display: block;
            font-size: 12px;
            font-weight: 600;
            color: var(--text-primary);
            margin-bottom: 6px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .form-group input {
            width: 100%;
            padding: 12px 16px;
            border: 1px solid var(--border-color);
            border-radius: 8px;
            background: var(--input-bg);
            color: var(--input-text);
            font-size: 14px;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }

        .form-group input:focus {
            outline: none;
            border-color: var(--accent-color);
            box-shadow: 0 0 0 3px rgba(0, 122, 255, 0.1);
        }

        .auth-button {
            width: 100%;
            padding: 12px 16px;
            background: var(--accent-color);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s ease, transform 0.1s ease;
        }

        .auth-button:hover {
            background: var(--accent-color-hover);
        }

        .auth-button:disabled {
            background: var(--disabled-bg);
            cursor: not-allowed;
            transform: none;
        }

        .status-message {
            margin-top: 12px;
            padding: 10px;
            border-radius: 6px;
            font-size: 12px;
            text-align: center;
            display: none;
        }

        .status-message.success {
            background: rgba(52, 199, 89, 0.15);
            color: var(--green-color);
            border: 1px solid rgba(52, 199, 89, 0.3);
            display: block;
        }

        .status-message.error {
            background: rgba(255, 59, 48, 0.15);
            color: var(--red-color);
            border: 1px solid rgba(255, 59, 48, 0.3);
            display: block;
        }

        .status-message.info {
            background: rgba(0, 122, 255, 0.15);
            color: var(--accent-color);
            border: 1px solid rgba(0, 122, 255, 0.3);
            display: block;
        }

        .login-footer {
            text-align: center;
        }

        .back-link {
            color: var(--text-secondary);
            text-decoration: none;
            font-size: 12px;
            transition: color 0.2s ease;
        }

        .back-link:hover {
            color: var(--accent-color);
        }

        /* Scrollbar Styling */
        ::-webkit-scrollbar {
            width: 6px;
            height: 6px;
        }

        ::-webkit-scrollbar-track {
            background: var(--bg-primary);
            border-radius: 3px;
        }

        ::-webkit-scrollbar-thumb {
            background: var(--border-color);
            border-radius: 3px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: var(--text-secondary);
        }
        
        /* Emoji Edit Styles */
        .emoji-edit-container {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .emoji-display {
            font-size: 20px;
            min-width: 30px;
            text-align: center;
        }
        
        .edit-emoji-btn {
            padding: 4px 8px;
            background: var(--accent-color);
            color: white;
            border: none;
            border-radius: 4px;
            font-size: 10px;
            cursor: pointer;
            transition: background 0.2s ease;
        }
        
        .edit-emoji-btn:hover {
            background: var(--accent-color-hover);
        }

        /* Admin Toggle Styles */
        .admin-toggle-container {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .toggle-admin-btn {
            padding: 4px 8px;
            background: var(--orange-color);
            color: white;
            border: none;
            border-radius: 4px;
            font-size: 10px;
            cursor: pointer;
            transition: background 0.2s ease;
        }

        .toggle-admin-btn:hover {
            background: #E6840A;
        }
        
        .emoji-picker-grid {
            display: grid;
            grid-template-columns: repeat(10, 1fr);
            gap: 8px;
            max-height: 300px;
            overflow-y: auto;
            padding: 10px;
            border: 1px solid var(--border-color);
            border-radius: 8px;
            background: var(--bg-primary);
            margin-bottom: 16px;
        }
        
        .emoji-picker-grid .emoji-option {
            font-size: 20px;
            padding: 8px;
            text-align: center;
            cursor: pointer;
            border-radius: 6px;
            transition: all 0.2s ease;
            border: 2px solid transparent;
        }
        
        .emoji-picker-grid .emoji-option:hover {
            background: var(--border-color);
            transform: scale(1.1);
        }
        
        .emoji-picker-grid .emoji-option.selected {
            background: var(--accent-color);
            border-color: var(--accent-color-hover);
        }
        
        .emoji-editor-actions {
            display: flex;
            gap: 8px;
            justify-content: flex-end;
        }
        
        .emoji-editor-actions button {
            padding: 8px 16px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 12px;
            transition: background 0.2s ease;
        }
        
        .emoji-editor-actions button:first-child {
            background: var(--accent-color);
            color: white;
        }
        
        .emoji-editor-actions button:first-child:hover:not(:disabled) {
            background: var(--accent-color-hover);
        }
        
        .emoji-editor-actions button:first-child:disabled {
            background: var(--disabled-bg);
            cursor: not-allowed;
        }
        
        .emoji-editor-actions button:last-child {
            background: var(--border-color);
            color: var(--text-primary);
        }
        
        .emoji-editor-actions button:last-child:hover {
            background: var(--text-secondary);
            color: white;
        }
        
        @media (max-width: 768px) {
            .emoji-picker-grid {
                grid-template-columns: repeat(6, 1fr);
            }
            
            .emoji-display {
                font-size: 16px;
            }
            
            .emoji-picker-grid .emoji-option {
                font-size: 16px;
                padding: 6px;
            }
        }
        """
    }

    // MARK: - Admin JavaScript Content
    public static func generateAdminJS() -> String {
        return """
        // Admin Panel JavaScript
        class AdminPanel {
            constructor() {
                this.users = [];
                this.filteredUsers = [];
                this.currentUser = null;
                this.init();
            }

            async init() {
                await this.loadUsers();
                this.updateStats();
                this.renderUsersTable();
            }

            async loadUsers() {
                try {
                    const response = await fetch('/admin/api/users');
                    if (!response.ok) {
                        if (response.status === 404 || response.status === 403) {
                            window.location.href = '/';
                            return;
                        }
                        throw new Error('Failed to load users');
                    }
                    
                    this.users = await response.json();
                    this.filteredUsers = [...this.users];
                } catch (error) {
                    console.error('Error loading users:', error);
                    this.showError('Failed to load users');
                }
            }

            updateStats() {
                const totalUsers = this.users.length;
                const activeUsers = this.users.filter(u => u.isEnabled).length;
                const disabledUsers = this.users.filter(u => !u.isEnabled).length;
                
                document.getElementById('total-users').textContent = totalUsers;
                document.getElementById('active-users').textContent = activeUsers;
                document.getElementById('disabled-users').textContent = disabledUsers;
            }

            renderUsersTable() {
                const tbody = document.getElementById('users-tbody');
                const userCount = document.getElementById('user-count');
                
                if (this.filteredUsers.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="9" class="loading">No users found</td></tr>';
                    userCount.textContent = '0';
                    return;
                }

                tbody.innerHTML = this.filteredUsers.map(user => `
                    <tr>
                        <td>#${user.userNumber}</td>
                        <td>${this.escapeHtml(user.username)}</td>
                        <td>${this.escapeHtml(user.emoji)}</td>
                        <td>
                            <span class="status-badge status-${user.isEnabled ? 'enabled' : 'disabled'}">
                                ${user.isEnabled ? 'Enabled' : 'Disabled'}
                            </span>
                        </td>
                        <td>${this.formatDate(user.createdAt)}</td>
                        <td>${user.lastLoginAt ? this.formatDate(user.lastLoginAt) : 'Never'}</td>
                        <td>${user.lastLoginIP || 'Unknown'}</td>
                        <td>${user.signCount}</td>
                        <td>
                            <div class="action-buttons">
                                <button class="action-btn btn-view" onclick="adminPanel.viewUser('${user.id}')">
                                    View
                                </button>
                                <label class="toggle-switch">
                                    <input type="checkbox" ${user.isEnabled ? 'checked' : ''} 
                                           onchange="adminPanel.toggleUser('${user.id}', this.checked)">
                                    <span class="slider"></span>
                                </label>
                                <button class="action-btn btn-delete" onclick="adminPanel.deleteUser('${user.id}')">
                                    Delete
                                </button>
                            </div>
                        </td>
                    </tr>
                `).join('');

                userCount.textContent = this.filteredUsers.length;
            }

            async toggleUser(userId, enabled) {
                try {
                    const response = await fetch('/admin/api/users/' + encodeURIComponent(userId) + '/toggle', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({ enabled })
                    });

                    if (!response.ok) {
                        throw new Error('Failed to toggle user status');
                    }

                    // Update local data
                    const user = this.users.find(u => u.id === userId);
                    if (user) {
                        user.isEnabled = enabled;
                    }

                    this.updateStats();
                    this.filterUsers(); // Re-render with current filters
                    this.showSuccess(`User ${enabled ? 'enabled' : 'disabled'} successfully`);
                } catch (error) {
                    console.error('Error toggling user:', error);
                    this.showError('Failed to toggle user status');
                    // Reload to reset the UI
                    this.loadUsers().then(() => this.renderUsersTable());
                }
            }

            async deleteUser(userId) {
                const user = this.users.find(u => u.id === userId);
                if (!user) return;

                if (!confirm(`Are you sure you want to delete user "${user.username}"? This action cannot be undone.`)) {
                    return;
                }

                try {
                    const response = await fetch('/admin/api/users/' + encodeURIComponent(userId), {
                        method: 'DELETE'
                    });

                    if (!response.ok) {
                        throw new Error('Failed to delete user');
                    }

                    this.users = this.users.filter(u => u.id !== userId);
                    this.filteredUsers = this.filteredUsers.filter(u => u.id !== userId);
                    this.updateStats();
                    this.renderUsersTable();
                    this.showSuccess('User deleted successfully');
                } catch (error) {
                    console.error('Error deleting user:', error);
                    this.showError('Failed to delete user');
                }
            }

            // Helper functions
            escapeHtml(text) {
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            }

            formatDate(dateString) {
                return new Date(dateString).toLocaleString();
            }

            showError(message) {
                console.error('Admin Error:', message);
                // You could add a toast notification here
            }

            showSuccess(message) {
                console.log('Admin Success:', message);
                // You could add a toast notification here
            }

            filterUsers() {
                const statusFilter = document.getElementById('status-filter').value;
                const searchTerm = document.getElementById('search-input').value.toLowerCase();

                this.filteredUsers = this.users.filter(user => {
                    const matchesStatus = statusFilter === 'all' || 
                                        (statusFilter === 'enabled' && user.isEnabled) ||
                                        (statusFilter === 'disabled' && !user.isEnabled);
                    
                    const matchesSearch = searchTerm === '' || 
                                        user.username.toLowerCase().includes(searchTerm);
                    
                    return matchesStatus && matchesSearch;
                });

                this.renderUsersTable();
            }

            viewUser(userId) {
                const user = this.users.find(u => u.id === userId);
                if (!user) return;
                
                // Populate modal fields
                document.getElementById('detail-id').textContent = user.id;
                document.getElementById('detail-user-number').textContent = user.userNumber;
                document.getElementById('detail-username').textContent = user.username;
                document.getElementById('detail-emoji').textContent = user.emoji || '👤';
                document.getElementById('detail-status').textContent = user.isEnabled ? 'Enabled' : 'Disabled';
                document.getElementById('detail-is-admin').textContent = user.isAdmin ? 'Yes' : 'No';
                document.getElementById('detail-created').textContent = this.formatDate(user.createdAt);
                document.getElementById('detail-last-login').textContent = user.lastLoginAt ? this.formatDate(user.lastLoginAt) : 'Never';
                document.getElementById('detail-ip').textContent = user.lastLoginIP || 'Unknown';
                document.getElementById('detail-sign-count').textContent = user.signCount;
                document.getElementById('detail-credential-id').textContent = user.credentialId;
                document.getElementById('detail-public-key').textContent = user.publicKey;
                
                // Store current user for emoji editing
                window.currentEditUser = user;
                
                // Show modal
                document.getElementById('user-details-modal').classList.remove('hidden');
            }
        }

        // Global functions for button clicks
        function refreshUsers() {
            if (window.adminPanel) {
                window.adminPanel.loadUsers().then(() => {
                    window.adminPanel.updateStats();
                    window.adminPanel.renderUsersTable();
                });
            }
        }

        function goBackToChat() {
            window.location.href = '/';
        }

        function filterUsers() {
            if (window.adminPanel) {
                window.adminPanel.filterUsers();
            }
        }

        function closeUserDetailsModal() {
            document.getElementById('user-details-modal').classList.add('hidden');
        }

        function disableByIP() {
            const ipAddress = document.getElementById('ip-address-input').value.trim();
            if (!ipAddress) {
                alert('Please enter an IP address');
                return;
            }

            if (!confirm(`Are you sure you want to disable all users with IP address "${ipAddress}"?`)) {
                return;
            }

            fetch('/admin/api/users/disable-by-ip', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ ipAddress })
            })
            .then(response => {
                if (!response.ok) {
                    throw new Error('Failed to disable users');
                }
                return response.json();
            })
            .then(() => {
                alert('Users disabled successfully');
                refreshUsers();
                document.getElementById('ip-address-input').value = '';
            })
            .catch(error => {
                console.error('Error disabling users:', error);
                alert('Failed to disable users');
            });
        }

        // Emoji editing functions
        function openEmojiEditor() {
            if (!window.currentEditUser) return;
            
            // Show emoji editor modal
            document.getElementById('emoji-editor-modal').classList.remove('hidden');
            
            // Clear previous selections
            document.querySelectorAll('.emoji-picker-grid .emoji-option').forEach(option => {
                option.classList.remove('selected');
            });
            
            // Select current emoji
            const currentEmoji = window.currentEditUser.emoji || '👤';
            const currentOption = document.querySelector(`.emoji-picker-grid .emoji-option[onclick="selectEmoji('${currentEmoji}')"]`);
            if (currentOption) {
                currentOption.classList.add('selected');
                document.getElementById('save-emoji-btn').disabled = true; // No change yet
            }
            
            window.selectedEmoji = currentEmoji;
        }
        
        function closeEmojiEditor() {
            document.getElementById('emoji-editor-modal').classList.add('hidden');
            window.selectedEmoji = null;
        }
        
        function selectEmoji(emoji) {
            // Update selection
            document.querySelectorAll('.emoji-picker-grid .emoji-option').forEach(option => {
                option.classList.remove('selected');
            });
            
            const selectedOption = document.querySelector(`.emoji-picker-grid .emoji-option[onclick="selectEmoji('${emoji}')"]`);
            if (selectedOption) {
                selectedOption.classList.add('selected');
            }
            
            window.selectedEmoji = emoji;
            
            // Enable save button if emoji changed
            const hasChanged = emoji !== (window.currentEditUser?.emoji || '👤');
            document.getElementById('save-emoji-btn').disabled = !hasChanged;
        }
        
        function saveEmojiChange() {
            if (!window.currentEditUser || !window.selectedEmoji) return;
            
            const userId = window.currentEditUser.id;
            const newEmoji = window.selectedEmoji;
            
            fetch(`/admin/api/users/${encodeURIComponent(userId)}/emoji`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ emoji: newEmoji })
            })
            .then(response => {
                if (!response.ok) {
                    throw new Error('Failed to update emoji');
                }
                return response.json();
            })
            .then(() => {
                // Update local data
                window.currentEditUser.emoji = newEmoji;
                
                // Update UI
                document.getElementById('detail-emoji').textContent = newEmoji;
                
                // Refresh the users table
                refreshUsers();
                
                // Close modal
                closeEmojiEditor();
                
                alert('Emoji updated successfully');
            })
            .catch(error => {
                console.error('Error updating emoji:', error);
                alert('Failed to update emoji');
            });
                }
        
        function toggleAdminRole() {
            if (!window.currentEditUser) return;
            
            const userId = window.currentEditUser.id;
            const currentIsAdmin = window.currentEditUser.isAdmin;
            const newIsAdmin = !currentIsAdmin;
            
            if (!confirm(`Are you sure you want to ${newIsAdmin ? 'grant' : 'revoke'} admin privileges for "${window.currentEditUser.username}"?`)) {
                return;
            }
            
            fetch(`/admin/api/users/${encodeURIComponent(userId)}/admin`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ isAdmin: newIsAdmin })
            })
            .then(response => {
                if (!response.ok) {
                    throw new Error('Failed to update admin role');
                }
                return response.json();
            })
            .then(() => {
                // Update local data
                window.currentEditUser.isAdmin = newIsAdmin;
                
                // Update UI
                document.getElementById('detail-is-admin').textContent = newIsAdmin ? 'Yes' : 'No';
                
                // Refresh the users table
                refreshUsers();
                
                alert(`Admin role ${newIsAdmin ? 'granted' : 'revoked'} successfully`);
            })
            .catch(error => {
                console.error('Error updating admin role:', error);
                alert('Failed to update admin role');
            });
        }
        
        // Initialize the admin panel when the page loads
        document.addEventListener('DOMContentLoaded', () => {
            console.log('Admin panel initializing...');
            window.adminPanel = new AdminPanel();
        });
        """
    }
    
    // MARK: - Admin Login JavaScript
    public static func generateAdminLoginJS() -> String {
        return """
        // Admin Login JavaScript
        
        function showStatus(message, type = 'info') {
            const statusEl = document.getElementById('status');
            statusEl.textContent = message;
            statusEl.className = `status-message ${type}`;
        }
        
        function setButtonState(disabled, text) {
            const btn = document.getElementById('authenticate-btn');
            btn.disabled = disabled;
            btn.textContent = text;
        }
        
        async function authenticateAdmin() {
            const username = document.getElementById('username').value.trim();
            
            if (!username) {
                showStatus('Please enter your username', 'error');
                return;
            }
            
            try {
                setButtonState(true, '🔄 Preparing authentication...');
                showStatus('Preparing WebAuthn authentication...', 'info');
                
                // Step 1: Get authentication options
                const optionsResponse = await fetch('/webauthn/authenticate/begin', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ username })
                });
                
                if (!optionsResponse.ok) {
                    throw new Error('Failed to get authentication options');
                }
                
                const options = await optionsResponse.json();
                
                setButtonState(true, '🔐 Authenticate with your passkey...');
                showStatus('Please use your passkey to authenticate', 'info');
                
                // Convert base64url to Uint8Array for WebAuthn
                function base64urlToUint8Array(base64url) {
                    const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
                    const padded = base64.padEnd(base64.length + (4 - base64.length % 4) % 4, '=');
                    const binary = atob(padded);
                    return new Uint8Array(binary.split('').map(char => char.charCodeAt(0)));
                }
                
                // Prepare WebAuthn options
                const webauthnOptions = {
                    publicKey: {
                        challenge: base64urlToUint8Array(options.publicKey.challenge),
                        allowCredentials: options.publicKey.allowCredentials?.map(cred => ({
                            type: cred.type,
                            id: base64urlToUint8Array(cred.id)
                        })),
                        timeout: options.publicKey.timeout || 60000,
                        userVerification: options.publicKey.userVerification || 'preferred'
                    }
                };
                
                // Step 2: Get WebAuthn assertion
                const assertion = await navigator.credentials.get(webauthnOptions);
                
                if (!assertion) {
                    throw new Error('Authentication cancelled or failed');
                }
                
                setButtonState(true, '✅ Verifying authentication...');
                showStatus('Verifying your authentication...', 'info');
                
                // Convert Uint8Array to base64 for transmission (same as chat system)
                function arrayBufferToBase64(buffer) {
                    let binary = '';
                    const bytes = new Uint8Array(buffer);
                    for (let i = 0; i < bytes.byteLength; i++) {
                        binary += String.fromCharCode(bytes[i]);
                    }
                    return btoa(binary);
                }
                
                // Convert Uint8Array to base64url for rawId
                function uint8ArrayToBase64url(uint8Array) {
                    const base64 = btoa(String.fromCharCode(...uint8Array));
                    return base64.replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=/g, '');
                }
                
                // Prepare response data (using same format as chat system)
                const authData = {
                    username: username,
                    id: assertion.id,
                    rawId: uint8ArrayToBase64url(new Uint8Array(assertion.rawId)),
                    response: {
                        clientDataJSON: arrayBufferToBase64(assertion.response.clientDataJSON),
                        authenticatorData: arrayBufferToBase64(assertion.response.authenticatorData),
                        signature: arrayBufferToBase64(assertion.response.signature)
                    },
                    type: assertion.type
                };
                
                // Step 3: Verify authentication with admin login endpoint
                const verifyResponse = await fetch('/admin/api/login', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(authData)
                });
                
                if (!verifyResponse.ok) {
                    const errorData = await verifyResponse.json().catch(() => ({}));
                    throw new Error(errorData.error || 'Authentication failed');
                }
                
                const result = await verifyResponse.json();
                
                if (result.success) {
                    showStatus('✅ Authentication successful! Redirecting...', 'success');
                    
                    // Store session info and redirect
                    if (result.sessionId) {
                        sessionStorage.setItem('adminSessionId', result.sessionId);
                    }
                    
                    setTimeout(() => {
                        window.location.href = '/admin/panel.html';
                    }, 1000);
                } else {
                    throw new Error(result.error || 'Authentication failed');
                }
                
            } catch (error) {
                console.error('Admin authentication error:', error);
                showStatus(`Authentication failed: ${error.message}`, 'error');
                setButtonState(false, '🔐 Authenticate with Passkey');
            }
        }
        
        // Allow Enter key to trigger authentication
        document.addEventListener('DOMContentLoaded', () => {
            document.getElementById('username').addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    authenticateAdmin();
                }
            });
        });
        """
    }

    // MARK: - Admin Login Page
    public static func generateAdminLoginHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>🛡️ Admin Login</title>
            <link rel="stylesheet" href="/admin/admin.css">
        </head>
        <body>
            <div class="login-container">
                <div class="login-card">
                    <div class="login-header">
                        <h1>🛡️ Admin Access</h1>
                        <p>Authenticate with your passkey</p>
                    </div>
                    
                    <div class="login-form">
                        <div class="form-group">
                            <label for="username">Username</label>
                            <input type="text" id="username" placeholder="Enter admin username" required>
                        </div>
                        
                        <button id="authenticate-btn" onclick="authenticateAdmin()" class="auth-button">
                            🔐 Authenticate
                        </button>
                        
                        <div id="status" class="status-message"></div>
                    </div>
                    
                    <div class="login-footer">
                        <a href="/" class="back-link">← Back to Chat</a>
                    </div>
                </div>
            </div>
            
            <script src="/admin/admin-login.js"></script>
        </body>
        </html>
        """
    }
}
