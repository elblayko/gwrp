-- ========================================================
-- GangWars RP (GW) - Production MariaDB Schema
-- Database Architecture: 100% Stored Procedures & Analytical Views
-- Engine: InnoDB | Standard: MariaDB 10.6+ / 11.x
-- ========================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- --------------------------------------------------------
-- 1. Table Structures
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS gw_players (
    steamid VARCHAR(20) NOT NULL PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    money BIGINT NOT NULL DEFAULT 1000,
    respect INT NOT NULL DEFAULT 0,
    gang VARCHAR(32) NOT NULL DEFAULT '',
    job VARCHAR(32) NOT NULL DEFAULT 'citizen',
    level INT NOT NULL DEFAULT 1,
    xp BIGINT NOT NULL DEFAULT 0,
    last_seen INT UNSIGNED NOT NULL DEFAULT 0,
    INDEX idx_players_gang (gang),
    INDEX idx_players_job (job)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_gangs (
    name VARCHAR(32) NOT NULL PRIMARY KEY,
    leader_steamid VARCHAR(20) NOT NULL,
    bank BIGINT NOT NULL DEFAULT 0,
    respect INT NOT NULL DEFAULT 0,
    created_at INT UNSIGNED NOT NULL DEFAULT 0,
    INDEX idx_gangs_leader (leader_steamid),
    INDEX idx_gangs_respect (respect DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_gang_members (
    steamid VARCHAR(20) NOT NULL PRIMARY KEY,
    gang VARCHAR(32) NOT NULL,
    rank VARCHAR(16) NOT NULL DEFAULT 'member',
    joined_at INT UNSIGNED NOT NULL DEFAULT 0,
    INDEX idx_members_gang (gang),
    CONSTRAINT fk_gw_gang_members FOREIGN KEY (gang) REFERENCES gw_gangs(name) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_inventory (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    steamid VARCHAR(20) NOT NULL,
    bag_index TINYINT UNSIGNED NOT NULL DEFAULT 0,
    slot_index TINYINT UNSIGNED NOT NULL DEFAULT 1,
    item_id VARCHAR(64) NOT NULL,
    item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
    amount INT NOT NULL DEFAULT 1,
    item_data JSON NULL,
    INDEX idx_inventory_steamid (steamid, bag_index, slot_index),
    INDEX idx_inventory_item (steamid, item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_player_bags (
    steamid VARCHAR(20) NOT NULL PRIMARY KEY,
    bag1 VARCHAR(64) NOT NULL DEFAULT '',
    bag2 VARCHAR(64) NOT NULL DEFAULT '',
    bag3 VARCHAR(64) NOT NULL DEFAULT '',
    bag4 VARCHAR(64) NOT NULL DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_turfs (
    map VARCHAR(64) NOT NULL,
    turf_id INT NOT NULL,
    name VARCHAR(64) NOT NULL,
    pos_x DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    pos_y DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    pos_z DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    radius INT NOT NULL DEFAULT 450,
    owner VARCHAR(32) NOT NULL DEFAULT 'neutral',
    tax_rate TINYINT UNSIGNED NOT NULL DEFAULT 10,
    PRIMARY KEY (map, turf_id),
    INDEX idx_turfs_owner (owner)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_settings (
    `key` VARCHAR(64) NOT NULL PRIMARY KEY,
    `val` TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gw_player_buffs (
    steamid VARCHAR(20) NOT NULL,
    buff_id VARCHAR(32) NOT NULL,
    duration DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    remaining DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    stacks TINYINT UNSIGNED NOT NULL DEFAULT 1,
    applied_at INT UNSIGNED NOT NULL DEFAULT 0,
    expires_at_unix INT UNSIGNED NOT NULL DEFAULT 0,
    data JSON NULL,
    PRIMARY KEY (steamid, buff_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- High-Performance Telemetry Table (Compound B-Trees + Monthly Range Partitioning)
CREATE TABLE IF NOT EXISTS gw_telemetry (
    log_id BIGINT UNSIGNED AUTO_INCREMENT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    unix_ts INT UNSIGNED NOT NULL DEFAULT (UNIX_TIMESTAMP()),
    category ENUM('ECONOMY', 'PLAYER_ACTION', 'ANTIDEBUG', 'COMBAT', 'TRADE') NOT NULL,
    action_type VARCHAR(48) NOT NULL,
    actor_steamid VARCHAR(20) NOT NULL,
    target_steamid VARCHAR(20) NULL,
    numeric_value DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    metadata JSON NULL,
    PRIMARY KEY (log_id, unix_ts),
    INDEX idx_actor_time (actor_steamid, created_at),
    INDEX idx_category_action_time (category, action_type, created_at),
    INDEX idx_target_time (target_steamid, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
PARTITION BY RANGE (unix_ts) (
    PARTITION p_2026_10 VALUES LESS THAN (1761955200),
    PARTITION p_2026_11 VALUES LESS THAN (1764547200),
    PARTITION p_2026_12 VALUES LESS THAN (1767225600),
    PARTITION p_2027_01 VALUES LESS THAN (1769904000),
    PARTITION p_future  VALUES LESS THAN MAXVALUE
);

-- --------------------------------------------------------
-- 2. Analytical & Dashboard Views (100% Analytical Reads)
-- --------------------------------------------------------

CREATE OR REPLACE VIEW v_player_profile AS
SELECT
    p.steamid,
    p.name,
    p.money,
    p.respect,
    p.gang,
    p.job,
    p.level,
    p.xp,
    p.last_seen,
    m.rank AS gang_rank
FROM gw_players p
LEFT JOIN gw_gang_members m ON p.steamid = m.steamid;

CREATE OR REPLACE VIEW v_player_inventory AS
SELECT
    id,
    steamid,
    bag_index,
    slot_index,
    item_id,
    item_type,
    amount,
    item_data
FROM gw_inventory;

CREATE OR REPLACE VIEW v_player_bags AS
SELECT
    steamid,
    bag1,
    bag2,
    bag3,
    bag4
FROM gw_player_bags;

CREATE OR REPLACE VIEW v_player_buffs AS
SELECT
    steamid,
    buff_id,
    duration,
    remaining,
    stacks,
    applied_at,
    expires_at_unix,
    data
FROM gw_player_buffs;

CREATE OR REPLACE VIEW v_gang_leaderboard AS
SELECT
    g.name,
    g.leader_steamid,
    p.name AS leader_name,
    g.bank,
    g.respect,
    g.created_at,
    COUNT(DISTINCT m.steamid) AS member_count,
    COUNT(DISTINCT t.turf_id) AS turf_count
FROM gw_gangs g
LEFT JOIN gw_players p ON g.leader_steamid = p.steamid
LEFT JOIN gw_gang_members m ON g.name = m.gang
LEFT JOIN gw_turfs t ON g.name = t.owner
GROUP BY g.name, g.leader_steamid, p.name, g.bank, g.respect, g.created_at
ORDER BY g.respect DESC, g.bank DESC;

CREATE OR REPLACE VIEW v_gang_roster AS
SELECT
    m.gang,
    m.steamid,
    m.rank,
    m.joined_at,
    p.name,
    p.money,
    p.job,
    p.level,
    p.last_seen
FROM gw_gang_members m
LEFT JOIN gw_players p ON m.steamid = p.steamid
ORDER BY
    CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END,
    m.joined_at ASC;

CREATE OR REPLACE VIEW v_map_turfs AS
SELECT
    map,
    turf_id,
    name,
    pos_x,
    pos_y,
    pos_z,
    radius,
    owner,
    tax_rate
FROM gw_turfs
ORDER BY turf_id ASC;

CREATE OR REPLACE VIEW v_settings AS
SELECT `key`, `val` FROM gw_settings;

CREATE OR REPLACE VIEW v_economy_metrics AS
SELECT
    category,
    action_type,
    COUNT(*) AS event_count,
    SUM(numeric_value) AS total_volume,
    AVG(numeric_value) AS average_volume,
    MIN(created_at) AS earliest_record,
    MAX(created_at) AS latest_record
FROM gw_telemetry
WHERE category IN ('ECONOMY', 'TRADE')
GROUP BY category, action_type;

CREATE OR REPLACE VIEW v_player_audit_history AS
SELECT
    log_id,
    created_at,
    category,
    action_type,
    actor_steamid,
    target_steamid,
    numeric_value,
    metadata
FROM gw_telemetry
ORDER BY created_at DESC;

CREATE OR REPLACE VIEW v_combat_telemetry AS
SELECT
    action_type AS weapon_class,
    COUNT(*) AS total_skirmishes,
    SUM(numeric_value) AS total_damage_dealt,
    AVG(numeric_value) AS avg_damage_per_engagement
FROM gw_telemetry
WHERE category = 'COMBAT'
GROUP BY action_type;

-- --------------------------------------------------------
-- 3. Stored Procedures (100% Writes via MariaDB Procedures)
-- --------------------------------------------------------

DELIMITER $$

-- Telemetry Logging Procedure
CREATE PROCEDURE gw_log_telemetry(
    IN p_category VARCHAR(20),
    IN p_action_type VARCHAR(48),
    IN p_actor_steamid VARCHAR(20),
    IN p_target_steamid VARCHAR(20),
    IN p_numeric_value DECIMAL(12, 2),
    IN p_metadata JSON
)
BEGIN
    INSERT INTO gw_telemetry (
        unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata
    ) VALUES (
        UNIX_TIMESTAMP(), p_category, p_action_type, p_actor_steamid, p_target_steamid, p_numeric_value, p_metadata
    );
END$$

-- Player Management Procedures
CREATE PROCEDURE gw_upsert_player(
    IN p_steamid VARCHAR(20),
    IN p_name VARCHAR(64),
    IN p_money BIGINT,
    IN p_respect INT,
    IN p_gang VARCHAR(32),
    IN p_job VARCHAR(32),
    IN p_level INT,
    IN p_xp BIGINT,
    IN p_last_seen INT UNSIGNED
)
BEGIN
    INSERT INTO gw_players (steamid, name, money, respect, gang, job, level, xp, last_seen)
    VALUES (p_steamid, p_name, p_money, p_respect, p_gang, p_job, p_level, p_xp, p_last_seen)
    ON DUPLICATE KEY UPDATE
        name = p_name,
        money = p_money,
        respect = p_respect,
        gang = p_gang,
        job = p_job,
        level = p_level,
        xp = p_xp,
        last_seen = p_last_seen;
END$$

CREATE PROCEDURE gw_update_player_money(
    IN p_steamid VARCHAR(20),
    IN p_money BIGINT,
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE gw_players
    SET money = p_money, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

CREATE PROCEDURE gw_update_player_gang(
    IN p_steamid VARCHAR(20),
    IN p_gang VARCHAR(32),
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE gw_players
    SET gang = p_gang, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

CREATE PROCEDURE gw_update_player_job(
    IN p_steamid VARCHAR(20),
    IN p_job VARCHAR(32),
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE gw_players
    SET job = p_job, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

CREATE PROCEDURE gw_update_player_level_xp(
    IN p_steamid VARCHAR(20),
    IN p_level INT,
    IN p_xp BIGINT,
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE gw_players
    SET level = p_level, xp = p_xp, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

-- Gangs & Atomic Vault Transfers
CREATE PROCEDURE gw_create_gang(
    IN p_gang_name VARCHAR(32),
    IN p_leader_steamid VARCHAR(20),
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO gw_gangs (name, leader_steamid, bank, respect, created_at)
    VALUES (p_gang_name, p_leader_steamid, 0, 0, p_unix_time)
    ON DUPLICATE KEY UPDATE leader_steamid = p_leader_steamid;

    INSERT INTO gw_gang_members (steamid, gang, rank, joined_at)
    VALUES (p_leader_steamid, p_gang_name, 'leader', p_unix_time)
    ON DUPLICATE KEY UPDATE gang = p_gang_name, rank = 'leader';

    UPDATE gw_players
    SET gang = p_gang_name, last_seen = p_unix_time
    WHERE steamid = p_leader_steamid;

    COMMIT;
END$$

CREATE PROCEDURE gw_add_gang_member(
    IN p_steamid VARCHAR(20),
    IN p_gang_name VARCHAR(32),
    IN p_rank VARCHAR(16),
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO gw_gang_members (steamid, gang, rank, joined_at)
    VALUES (p_steamid, p_gang_name, p_rank, p_unix_time)
    ON DUPLICATE KEY UPDATE gang = p_gang_name, rank = p_rank;

    UPDATE gw_players
    SET gang = p_gang_name, last_seen = p_unix_time
    WHERE steamid = p_steamid;

    COMMIT;
END$$

CREATE PROCEDURE gw_remove_gang_member(
    IN p_steamid VARCHAR(20)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    DELETE FROM gw_gang_members WHERE steamid = p_steamid;
    UPDATE gw_players SET gang = '' WHERE steamid = p_steamid;

    COMMIT;
END$$

CREATE PROCEDURE gw_add_gang_bank(
    IN p_gang_name VARCHAR(32),
    IN p_amount BIGINT
)
BEGIN
    UPDATE gw_gangs
    SET bank = GREATEST(0, bank + p_amount)
    WHERE name = p_gang_name;
END$$

CREATE PROCEDURE gw_transfer_gang_vault(
    IN p_steamid VARCHAR(20),
    IN p_gang_name VARCHAR(32),
    IN p_delta BIGINT,
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE v_player_money BIGINT DEFAULT 0;
    DECLARE v_gang_bank BIGINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT money INTO v_player_money FROM gw_players WHERE steamid = p_steamid FOR UPDATE;
    SELECT bank INTO v_gang_bank FROM gw_gangs WHERE name = p_gang_name FOR UPDATE;

    -- p_delta > 0: Deposit from player wallet into gang bank
    -- p_delta < 0: Withdrawal from gang bank into player wallet
    IF (p_delta > 0 AND v_player_money >= p_delta) THEN
        UPDATE gw_players SET money = money - p_delta, last_seen = p_unix_time WHERE steamid = p_steamid;
        UPDATE gw_gangs SET bank = bank + p_delta WHERE name = p_gang_name;
    ELSEIF (p_delta < 0 AND v_gang_bank >= ABS(p_delta)) THEN
        UPDATE gw_players SET money = money + ABS(p_delta), last_seen = p_unix_time WHERE steamid = p_steamid;
        UPDATE gw_gangs SET bank = bank - ABS(p_delta) WHERE name = p_gang_name;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance for gang vault transaction';
    END IF;

    COMMIT;
END$$

CREATE PROCEDURE gw_disband_gang(
    IN p_gang_name VARCHAR(32)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE gw_players SET gang = '' WHERE gang = p_gang_name;
    DELETE FROM gw_gang_members WHERE gang = p_gang_name;
    DELETE FROM gw_gangs WHERE name = p_gang_name;

    COMMIT;
END$$

-- Inventory & Bag Storage Procedures
CREATE PROCEDURE gw_set_inventory_slot(
    IN p_steamid VARCHAR(20),
    IN p_bag_index TINYINT UNSIGNED,
    IN p_slot_index TINYINT UNSIGNED,
    IN p_item_id VARCHAR(64),
    IN p_item_type VARCHAR(32),
    IN p_amount INT,
    IN p_item_data JSON
)
BEGIN
    DELETE FROM gw_inventory
    WHERE steamid = p_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;

    IF p_amount > 0 THEN
        INSERT INTO gw_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data)
        VALUES (p_steamid, p_bag_index, p_slot_index, p_item_id, p_item_type, p_amount, p_item_data);
    END IF;
END$$

CREATE PROCEDURE gw_delete_inventory_slot(
    IN p_steamid VARCHAR(20),
    IN p_bag_index TINYINT UNSIGNED,
    IN p_slot_index TINYINT UNSIGNED
)
BEGIN
    DELETE FROM gw_inventory
    WHERE steamid = p_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;
END$$

CREATE PROCEDURE gw_move_inventory_slot(
    IN p_steamid VARCHAR(20),
    IN p_from_bag TINYINT UNSIGNED,
    IN p_from_slot TINYINT UNSIGNED,
    IN p_to_bag TINYINT UNSIGNED,
    IN p_to_slot TINYINT UNSIGNED
)
BEGIN
    DECLARE v_src_id BIGINT UNSIGNED;
    DECLARE v_src_item VARCHAR(64);
    DECLARE v_src_type VARCHAR(32);
    DECLARE v_src_amt INT;
    DECLARE v_src_data JSON;

    DECLARE v_dst_id BIGINT UNSIGNED;
    DECLARE v_dst_item VARCHAR(64);
    DECLARE v_dst_type VARCHAR(32);
    DECLARE v_dst_amt INT;
    DECLARE v_dst_data JSON;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT id, item_id, item_type, amount, item_data
    INTO v_src_id, v_src_item, v_src_type, v_src_amt, v_src_data
    FROM gw_inventory
    WHERE steamid = p_steamid AND bag_index = p_from_bag AND slot_index = p_from_slot
    FOR UPDATE;

    IF v_src_id IS NOT NULL THEN
        SELECT id, item_id, item_type, amount, item_data
        INTO v_dst_id, v_dst_item, v_dst_type, v_dst_amt, v_dst_data
        FROM gw_inventory
        WHERE steamid = p_steamid AND bag_index = p_to_bag AND slot_index = p_to_slot
        FOR UPDATE;

        IF v_dst_id IS NULL THEN
            UPDATE gw_inventory
            SET bag_index = p_to_bag, slot_index = p_to_slot
            WHERE id = v_src_id;
        ELSEIF v_src_item = v_dst_item THEN
            -- Combine identical item stacks
            UPDATE gw_inventory SET amount = amount + v_src_amt WHERE id = v_dst_id;
            DELETE FROM gw_inventory WHERE id = v_src_id;
        ELSE
            -- Swap slots
            UPDATE gw_inventory SET bag_index = p_to_bag, slot_index = p_to_slot WHERE id = v_src_id;
            UPDATE gw_inventory SET bag_index = p_from_bag, slot_index = p_from_slot WHERE id = v_dst_id;
        END IF;
    END IF;

    COMMIT;
END$$

CREATE PROCEDURE gw_set_player_bags(
    IN p_steamid VARCHAR(20),
    IN p_bag1 VARCHAR(64),
    IN p_bag2 VARCHAR(64),
    IN p_bag3 VARCHAR(64),
    IN p_bag4 VARCHAR(64)
)
BEGIN
    INSERT INTO gw_player_bags (steamid, bag1, bag2, bag3, bag4)
    VALUES (p_steamid, p_bag1, p_bag2, p_bag3, p_bag4)
    ON DUPLICATE KEY UPDATE
        bag1 = p_bag1,
        bag2 = p_bag2,
        bag3 = p_bag3,
        bag4 = p_bag4;
END$$

-- Turf & Territory Procedures
CREATE PROCEDURE gw_save_map_turf(
    IN p_map VARCHAR(64),
    IN p_turf_id INT,
    IN p_name VARCHAR(64),
    IN p_pos_x DECIMAL(10, 2),
    IN p_pos_y DECIMAL(10, 2),
    IN p_pos_z DECIMAL(10, 2),
    IN p_radius INT,
    IN p_owner VARCHAR(32),
    IN p_tax_rate TINYINT UNSIGNED
)
BEGIN
    INSERT INTO gw_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner, tax_rate)
    VALUES (p_map, p_turf_id, p_name, p_pos_x, p_pos_y, p_pos_z, p_radius, p_owner, p_tax_rate)
    ON DUPLICATE KEY UPDATE
        name = p_name,
        pos_x = p_pos_x,
        pos_y = p_pos_y,
        pos_z = p_pos_z,
        radius = p_radius,
        owner = p_owner,
        tax_rate = p_tax_rate;
END$$

CREATE PROCEDURE gw_clear_map_turfs(
    IN p_map VARCHAR(64)
)
BEGIN
    DELETE FROM gw_turfs WHERE map = p_map;
END$$

CREATE PROCEDURE gw_delete_map_turf(
    IN p_map VARCHAR(64),
    IN p_turf_id INT
)
BEGIN
    DELETE FROM gw_turfs WHERE map = p_map AND turf_id = p_turf_id;
END$$

CREATE PROCEDURE gw_set_turf_tax(
    IN p_map VARCHAR(64),
    IN p_turf_id INT,
    IN p_tax_rate TINYINT UNSIGNED
)
BEGIN
    UPDATE gw_turfs
    SET tax_rate = p_tax_rate
    WHERE map = p_map AND turf_id = p_turf_id;
END$$

-- Atomic Economy & Protection Tax Collection
CREATE PROCEDURE gw_collect_printer_taxed(
    IN p_actor_steamid VARCHAR(20),
    IN p_controlling_gang VARCHAR(32),
    IN p_payout_amount BIGINT,
    IN p_tax_amount BIGINT,
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE gw_players
    SET money = money + p_payout_amount, last_seen = p_unix_time
    WHERE steamid = p_actor_steamid;

    IF p_tax_amount > 0 AND p_controlling_gang != '' AND p_controlling_gang != 'neutral' AND p_controlling_gang != 'Police' THEN
        UPDATE gw_gangs
        SET bank = bank + p_tax_amount
        WHERE name = p_controlling_gang;
    END IF;

    COMMIT;
END$$

-- Player Buff Procedures
CREATE PROCEDURE gw_save_player_buff(
    IN p_steamid VARCHAR(20),
    IN p_buff_id VARCHAR(32),
    IN p_duration DECIMAL(10, 2),
    IN p_remaining DECIMAL(10, 2),
    IN p_stacks TINYINT UNSIGNED,
    IN p_applied_at INT UNSIGNED,
    IN p_expires_at_unix INT UNSIGNED,
    IN p_data JSON
)
BEGIN
    INSERT INTO gw_player_buffs (
        steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data
    ) VALUES (
        p_steamid, p_buff_id, p_duration, p_remaining, p_stacks, p_applied_at, p_expires_at_unix, p_data
    ) ON DUPLICATE KEY UPDATE
        duration = p_duration,
        remaining = p_remaining,
        stacks = p_stacks,
        applied_at = p_applied_at,
        expires_at_unix = p_expires_at_unix,
        data = p_data;
END$$

CREATE PROCEDURE gw_delete_player_buff(
    IN p_steamid VARCHAR(20),
    IN p_buff_id VARCHAR(32)
)
BEGIN
    DELETE FROM gw_player_buffs
    WHERE steamid = p_steamid AND buff_id = p_buff_id;
END$$

CREATE PROCEDURE gw_clear_player_buffs(
    IN p_steamid VARCHAR(20)
)
BEGIN
    DELETE FROM gw_player_buffs
    WHERE steamid = p_steamid;
END$$

-- Global Settings Procedure
CREATE PROCEDURE gw_set_setting(
    IN p_key VARCHAR(64),
    IN p_val TEXT
)
BEGIN
    INSERT INTO gw_settings (`key`, `val`)
    VALUES (p_key, p_val)
    ON DUPLICATE KEY UPDATE `val` = p_val;
END$$

DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;

