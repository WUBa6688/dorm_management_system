-- 宿舍管理系统数据库 V1.0，依据 2026-11-23 需求规格说明书。
-- 目标：MySQL 8.4+；实际验证版本见数据库设计说明书。
-- 仅用于空库初始化；已有库应使用评审后的迁移，不禁用外键、不删除历史数据。
CREATE DATABASE IF NOT EXISTS dormitory_management
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE dormitory_management;
SET NAMES utf8mb4;
SET SESSION time_zone = '+08:00';

CREATE TABLE student (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '学生主键',
  student_no VARCHAR(32) NOT NULL COMMENT '全局唯一学号，建档后不可改',
  name VARCHAR(64) NOT NULL COMMENT '学生姓名',
  gender CHAR(1) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'M男 F女',
  college VARCHAR(100) NOT NULL COMMENT '院系',
  major VARCHAR(100) NULL COMMENT '专业',
  class_name VARCHAR(100) NOT NULL COMMENT '班级',
  phone VARCHAR(32) NULL COMMENT '联系方式，仅授权角色可见',
  avatar_url VARCHAR(512) NULL COMMENT '可选头像相对路径，兼容旧README',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '建档时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_student_no (student_no),
  KEY idx_student_class (class_name, id),
  KEY idx_student_name (name, id),
  CONSTRAINT ck_student_gender CHECK (gender IN ('M','F')),
  CONSTRAINT ck_student_status CHECK (status IN (0,1)),
  CONSTRAINT ck_student_required CHECK (CHAR_LENGTH(TRIM(student_no)) > 0 AND CHAR_LENGTH(TRIM(name)) > 0)
) ENGINE=InnoDB COMMENT='学生档案，停用保留历史';

CREATE TABLE sys_user (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '账号主键',
  username VARCHAR(64) NOT NULL COMMENT '登录名，不区分大小写，全局唯一',
  password_hash VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'BCrypt哈希，禁止明文',
  role VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'ADMIN MANAGER STUDENT',
  student_id BIGINT UNSIGNED NULL COMMENT '学生角色必须绑定，其他角色必须为空',
  display_name VARCHAR(64) NOT NULL COMMENT '显示姓名',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  credential_version BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '停用或改密递增，使旧会话失效',
  last_login_at DATETIME(3) NULL COMMENT '最近成功登录时间',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_username (username),
  UNIQUE KEY uk_user_student (student_id),
  KEY idx_user_role_status (role, status, id),
  CONSTRAINT fk_user_student FOREIGN KEY (student_id) REFERENCES student(id),
  CONSTRAINT ck_user_role CHECK (role IN ('ADMIN','MANAGER','STUDENT')),
  CONSTRAINT ck_user_status CHECK (status IN (0,1)),
  CONSTRAINT ck_user_binding CHECK ((role = 'STUDENT' AND student_id IS NOT NULL) OR (role IN ('ADMIN','MANAGER') AND student_id IS NULL)),
  CONSTRAINT ck_user_required CHECK (CHAR_LENGTH(TRIM(username)) > 0 AND CHAR_LENGTH(password_hash) = 60)
) ENGINE=InnoDB COMMENT='三类业务账号，学生最多一个账号';

CREATE TABLE dorm_building (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '楼栋主键',
  building_no VARCHAR(32) NOT NULL COMMENT '全局唯一楼栋编号',
  building_name VARCHAR(100) NOT NULL COMMENT '楼栋名称',
  floors SMALLINT UNSIGNED NOT NULL COMMENT '总楼层数，楼层从1开始',
  gender_limit VARCHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ALL' COMMENT 'M F ALL',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_building_no (building_no),
  CONSTRAINT ck_building_floors CHECK (floors > 0),
  CONSTRAINT ck_building_gender CHECK (gender_limit IN ('M','F','ALL')),
  CONSTRAINT ck_building_status CHECK (status IN (0,1))
) ENGINE=InnoDB COMMENT='楼栋资源';

CREATE TABLE manager_building (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '授权主键',
  user_id BIGINT UNSIGNED NOT NULL COMMENT '宿管账号，仅允许MANAGER',
  building_id BIGINT UNSIGNED NOT NULL COMMENT '授权楼栋',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1有效授权 0撤销',
  granted_by BIGINT UNSIGNED NOT NULL COMMENT '最近授权管理员',
  granted_at DATETIME(3) NOT NULL COMMENT '最近授权时间',
  revoked_by BIGINT UNSIGNED NULL COMMENT '最近撤权管理员',
  revoked_at DATETIME(3) NULL COMMENT '最近撤权时间',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '首次创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_manager_building (user_id, building_id),
  KEY idx_manager_building_reverse (building_id, status, user_id),
  CONSTRAINT fk_manager_user FOREIGN KEY (user_id) REFERENCES sys_user(id),
  CONSTRAINT fk_manager_building FOREIGN KEY (building_id) REFERENCES dorm_building(id),
  CONSTRAINT fk_manager_granter FOREIGN KEY (granted_by) REFERENCES sys_user(id),
  CONSTRAINT fk_manager_revoker FOREIGN KEY (revoked_by) REFERENCES sys_user(id),
  CONSTRAINT ck_manager_state CHECK ((status = 1 AND revoked_by IS NULL AND revoked_at IS NULL) OR (status = 0 AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL AND revoked_at >= granted_at))
) ENGINE=InnoDB COMMENT='宿管楼栋多对多授权，重新授权复用原行';

CREATE TABLE dorm_room (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '房间主键',
  building_id BIGINT UNSIGNED NOT NULL COMMENT '所属楼栋，创建后不迁移归属',
  room_no VARCHAR(32) NOT NULL COMMENT '楼栋内唯一房间号',
  floor_no SMALLINT UNSIGNED NOT NULL COMMENT '楼层，须不超过楼栋总楼层',
  gender_limit VARCHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ALL' COMMENT 'M F ALL，与楼栋限制同时生效',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_room_number (building_id, room_no),
  KEY idx_room_filter (building_id, status, floor_no, id),
  CONSTRAINT fk_room_building FOREIGN KEY (building_id) REFERENCES dorm_building(id),
  CONSTRAINT ck_room_floor CHECK (floor_no > 0),
  CONSTRAINT ck_room_gender CHECK (gender_limit IN ('M','F','ALL')),
  CONSTRAINT ck_room_status CHECK (status IN (0,1))
) ENGINE=InnoDB COMMENT='房间，容量由启用床位数量计算';

CREATE TABLE dorm_bed (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '床位主键',
  room_id BIGINT UNSIGNED NOT NULL COMMENT '所属房间，创建后不迁移归属',
  bed_no VARCHAR(16) NOT NULL COMMENT '房间内唯一床号',
  status TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1启用 0停用，不表达占用',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_bed_number (room_id, bed_no),
  KEY idx_bed_room_status (room_id, status, id),
  CONSTRAINT fk_bed_room FOREIGN KEY (room_id) REFERENCES dorm_room(id),
  CONSTRAINT ck_bed_status CHECK (status IN (0,1))
) ENGINE=InnoDB COMMENT='床位资源，占用以ACTIVE住宿记录为准';

CREATE TABLE stay_record (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '住宿记录主键',
  student_id BIGINT UNSIGNED NOT NULL COMMENT '住宿学生',
  bed_id BIGINT UNSIGNED NOT NULL COMMENT '住宿床位',
  transfer_from_id BIGINT UNSIGNED NULL COMMENT '调宿源住宿记录，普通入住为空',
  location_snapshot JSON NOT NULL COMMENT '入住时楼栋房间床号快照，字段见设计书',
  checkin_at DATETIME(3) NOT NULL COMMENT '入住时间，调宿与原记录结束时点相同',
  checkout_at DATETIME(3) NULL COMMENT '结束时间，生效记录为空',
  status VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE生效 ENDED结束',
  end_type VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT 'CHECKOUT退宿 TRANSFER调宿',
  end_reason VARCHAR(500) NULL COMMENT '结束原因，结束时必填',
  checkin_by BIGINT UNSIGNED NOT NULL COMMENT '入住办理人',
  checkout_by BIGINT UNSIGNED NULL COMMENT '结束办理人',
  active_student_id BIGINT UNSIGNED GENERATED ALWAYS AS (CASE WHEN status = 'ACTIVE' THEN student_id ELSE NULL END) STORED COMMENT '数据库生成，不接受客户端写入',
  active_bed_id BIGINT UNSIGNED GENERATED ALWAYS AS (CASE WHEN status = 'ACTIVE' THEN bed_id ELSE NULL END) STORED COMMENT '数据库生成，不接受客户端写入',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_stay_active_student (active_student_id),
  UNIQUE KEY uk_stay_active_bed (active_bed_id),
  UNIQUE KEY uk_stay_transfer_source (transfer_from_id),
  KEY idx_stay_student_history (student_id, checkin_at, id),
  KEY idx_stay_bed_history (bed_id, checkin_at, id),
  KEY idx_stay_checkin (checkin_at, id),
  KEY idx_stay_checkout (end_type, checkout_at, id),
  CONSTRAINT fk_stay_student FOREIGN KEY (student_id) REFERENCES student(id),
  CONSTRAINT fk_stay_bed FOREIGN KEY (bed_id) REFERENCES dorm_bed(id),
  CONSTRAINT fk_stay_transfer FOREIGN KEY (transfer_from_id) REFERENCES stay_record(id),
  CONSTRAINT fk_stay_checkin_user FOREIGN KEY (checkin_by) REFERENCES sys_user(id),
  CONSTRAINT fk_stay_checkout_user FOREIGN KEY (checkout_by) REFERENCES sys_user(id),
  CONSTRAINT ck_stay_location CHECK (JSON_TYPE(location_snapshot) = 'OBJECT'),
  CONSTRAINT ck_stay_state CHECK (
    (status = 'ACTIVE' AND checkout_at IS NULL AND end_type IS NULL AND end_reason IS NULL AND checkout_by IS NULL)
    OR (status = 'ENDED' AND checkout_at IS NOT NULL AND checkout_at >= checkin_at AND end_type IS NOT NULL AND end_type IN ('CHECKOUT','TRANSFER') AND end_reason IS NOT NULL AND CHAR_LENGTH(TRIM(end_reason)) > 0 AND checkout_by IS NOT NULL)
  )
) ENGINE=InnoDB COMMENT='住宿历史及当前住宿，生成列唯一索引保障单人单床';

CREATE TABLE stay_change_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '住宿办理流水主键',
  operation_no CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务端生成UUID，成功办理唯一编号',
  student_id BIGINT UNSIGNED NOT NULL COMMENT '办理学生',
  action_type VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'CHECKIN CHECKOUT TRANSFER',
  from_stay_id BIGINT UNSIGNED NULL COMMENT '原住宿记录',
  to_stay_id BIGINT UNSIGNED NULL COMMENT '新住宿记录',
  operator_id BIGINT UNSIGNED NOT NULL COMMENT '办理人',
  operated_at DATETIME(3) NOT NULL COMMENT '办理时间，与住宿变更时点一致',
  remark VARCHAR(500) NULL COMMENT '办理原因或备注',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '流水写入时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_stay_log_operation (operation_no),
  UNIQUE KEY uk_stay_log_from (from_stay_id),
  UNIQUE KEY uk_stay_log_to (to_stay_id),
  KEY idx_stay_log_student (student_id, operated_at, id),
  KEY idx_stay_log_report (action_type, operated_at, id),
  KEY idx_stay_log_operator (operator_id, operated_at, id),
  CONSTRAINT fk_stay_log_student FOREIGN KEY (student_id) REFERENCES student(id),
  CONSTRAINT fk_stay_log_from FOREIGN KEY (from_stay_id) REFERENCES stay_record(id),
  CONSTRAINT fk_stay_log_to FOREIGN KEY (to_stay_id) REFERENCES stay_record(id),
  CONSTRAINT fk_stay_log_operator FOREIGN KEY (operator_id) REFERENCES sys_user(id),
  CONSTRAINT ck_stay_log_action CHECK (
    (action_type = 'CHECKIN' AND from_stay_id IS NULL AND to_stay_id IS NOT NULL)
    OR (action_type = 'CHECKOUT' AND from_stay_id IS NOT NULL AND to_stay_id IS NULL)
    OR (action_type = 'TRANSFER' AND from_stay_id IS NOT NULL AND to_stay_id IS NOT NULL AND from_stay_id <> to_stay_id)
  )
) ENGINE=InnoDB COMMENT='只追加的成功办理流水，调宿一次记一笔';

CREATE TABLE repair_order (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '工单主键',
  order_no VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务端生成的唯一工单号',
  student_id BIGINT UNSIGNED NOT NULL COMMENT '报修学生',
  stay_id BIGINT UNSIGNED NOT NULL COMMENT '提交时住宿记录',
  room_id BIGINT UNSIGNED NOT NULL COMMENT '故障发生房间，调宿后不变',
  location_snapshot JSON NOT NULL COMMENT '提交时地点快照',
  category VARCHAR(32) NOT NULL COMMENT '故障类别 WATER ELECTRIC FURNITURE OTHER',
  title VARCHAR(100) NOT NULL COMMENT '工单标题',
  description TEXT NOT NULL COMMENT '故障描述',
  contact_phone VARCHAR(32) NOT NULL COMMENT '提交时联系信息，禁止写入审计JSON',
  status VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING PROCESSING COMPLETED CANCELLED REJECTED',
  accepted_by BIGINT UNSIGNED NULL COMMENT '受理人',
  accepted_at DATETIME(3) NULL COMMENT '受理时间',
  closed_by BIGINT UNSIGNED NULL COMMENT '完成、撤销或退回操作人',
  closed_at DATETIME(3) NULL COMMENT '终结时间，完成量按COMPLETED筛选',
  close_remark VARCHAR(1000) NULL COMMENT '处理结果、撤销说明或退回原因',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '状态转换乐观锁',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '提交时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_repair_order_no (order_no),
  KEY idx_repair_student (student_id, created_at, id),
  KEY idx_repair_room_status (room_id, status, created_at, id),
  KEY idx_repair_status_date (status, created_at, id),
  KEY idx_repair_completed (status, closed_at, id),
  CONSTRAINT fk_repair_student FOREIGN KEY (student_id) REFERENCES student(id),
  CONSTRAINT fk_repair_stay FOREIGN KEY (stay_id) REFERENCES stay_record(id),
  CONSTRAINT fk_repair_room FOREIGN KEY (room_id) REFERENCES dorm_room(id),
  CONSTRAINT fk_repair_acceptor FOREIGN KEY (accepted_by) REFERENCES sys_user(id),
  CONSTRAINT fk_repair_closer FOREIGN KEY (closed_by) REFERENCES sys_user(id),
  CONSTRAINT ck_repair_category CHECK (category IN ('WATER','ELECTRIC','FURNITURE','OTHER')),
  CONSTRAINT ck_repair_location CHECK (JSON_TYPE(location_snapshot) = 'OBJECT'),
  CONSTRAINT ck_repair_accept_time CHECK ((accepted_at IS NULL AND accepted_by IS NULL) OR (accepted_at IS NOT NULL AND accepted_by IS NOT NULL AND accepted_at >= created_at)),
  CONSTRAINT ck_repair_close_time CHECK ((closed_at IS NULL AND closed_by IS NULL AND close_remark IS NULL) OR (closed_at IS NOT NULL AND closed_by IS NOT NULL AND close_remark IS NOT NULL AND CHAR_LENGTH(TRIM(close_remark)) > 0 AND closed_at >= created_at)),
  CONSTRAINT ck_repair_state CHECK (
    (status = 'PENDING' AND accepted_at IS NULL AND closed_at IS NULL)
    OR (status = 'PROCESSING' AND accepted_at IS NOT NULL AND closed_at IS NULL)
    OR (status = 'COMPLETED' AND accepted_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= accepted_at)
    OR (status IN ('CANCELLED','REJECTED') AND accepted_at IS NULL AND closed_at IS NOT NULL)
  )
) ENGINE=InnoDB COMMENT='报修发生地固定，终态不可再流转';

CREATE TABLE visitor_record (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '来访记录主键',
  student_id BIGINT UNSIGNED NOT NULL COMMENT '被访学生',
  stay_id BIGINT UNSIGNED NOT NULL COMMENT '到访时住宿关系',
  room_id BIGINT UNSIGNED NOT NULL COMMENT '被访房间，原楼栋负责签离',
  location_snapshot JSON NOT NULL COMMENT '到访时地点快照',
  visitor_name VARCHAR(64) NOT NULL COMMENT '访客姓名',
  visitor_phone VARCHAR(32) NOT NULL COMMENT '访客联系方式，限制工作人员访问',
  purpose VARCHAR(500) NOT NULL COMMENT '来访事由',
  arrive_at DATETIME(3) NOT NULL COMMENT '实际到访时间',
  expected_leave_at DATETIME(3) NULL COMMENT '预计离开时间，可选',
  leave_at DATETIME(3) NULL COMMENT '实际离开时间',
  registered_by BIGINT UNSIGNED NOT NULL COMMENT '登记人',
  left_by BIGINT UNSIGNED NULL COMMENT '签离人',
  status VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'VISITING' COMMENT 'VISITING LEFT VOIDED',
  void_reason VARCHAR(500) NULL COMMENT '作废原因',
  voided_by BIGINT UNSIGNED NULL COMMENT '作废人',
  voided_at DATETIME(3) NULL COMMENT '作废时间',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '录入时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  KEY idx_visitor_room_date (room_id, arrive_at, id),
  KEY idx_visitor_current (status, arrive_at, id),
  KEY idx_visitor_student (student_id, arrive_at, id),
  CONSTRAINT fk_visitor_student FOREIGN KEY (student_id) REFERENCES student(id),
  CONSTRAINT fk_visitor_stay FOREIGN KEY (stay_id) REFERENCES stay_record(id),
  CONSTRAINT fk_visitor_room FOREIGN KEY (room_id) REFERENCES dorm_room(id),
  CONSTRAINT fk_visitor_register FOREIGN KEY (registered_by) REFERENCES sys_user(id),
  CONSTRAINT fk_visitor_left FOREIGN KEY (left_by) REFERENCES sys_user(id),
  CONSTRAINT fk_visitor_voider FOREIGN KEY (voided_by) REFERENCES sys_user(id),
  CONSTRAINT ck_visitor_location CHECK (JSON_TYPE(location_snapshot) = 'OBJECT'),
  CONSTRAINT ck_visitor_expected CHECK (expected_leave_at IS NULL OR expected_leave_at >= arrive_at),
  CONSTRAINT ck_visitor_leave CHECK ((leave_at IS NULL AND left_by IS NULL) OR (leave_at IS NOT NULL AND left_by IS NOT NULL AND leave_at >= arrive_at)),
  CONSTRAINT ck_visitor_void CHECK ((status <> 'VOIDED' AND voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR (status = 'VOIDED' AND voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL AND CHAR_LENGTH(TRIM(void_reason)) > 0)),
  CONSTRAINT ck_visitor_state CHECK ((status = 'VISITING' AND leave_at IS NULL) OR (status = 'LEFT' AND leave_at IS NOT NULL) OR status = 'VOIDED')
) ENGINE=InnoDB COMMENT='来访登记，误登作废后另建';

CREATE TABLE late_return_record (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '晚归主键',
  student_id BIGINT UNSIGNED NOT NULL COMMENT '晚归学生',
  stay_id BIGINT UNSIGNED NOT NULL COMMENT '归寝时覆盖该时刻的住宿关系',
  room_id BIGINT UNSIGNED NOT NULL COMMENT '发生房间，按其楼栋授权',
  location_snapshot JSON NOT NULL COMMENT '归寝时地点快照',
  return_at DATETIME(3) NOT NULL COMMENT 'Asia/Shanghai实际归寝时间',
  business_date DATE GENERATED ALWAYS AS (CASE WHEN TIME(return_at) < '06:00:00' THEN DATE(return_at - INTERVAL 1 DAY) ELSE DATE(return_at) END) STORED COMMENT '凌晨归入前一业务日',
  reason VARCHAR(500) NOT NULL COMMENT '晚归原因',
  remark VARCHAR(500) NULL COMMENT '备注',
  status VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'VALID' COMMENT 'VALID有效 VOIDED作废',
  valid_business_date DATE GENERATED ALWAYS AS (CASE WHEN status = 'VALID' THEN business_date ELSE NULL END) STORED COMMENT '有效记录唯一性辅助列',
  created_by BIGINT UNSIGNED NOT NULL COMMENT '登记人',
  updated_by BIGINT UNSIGNED NOT NULL COMMENT '最近登记或更正人',
  correction_reason VARCHAR(500) NULL COMMENT '最近更正原因，完整变更在操作日志',
  void_reason VARCHAR(500) NULL COMMENT '作废原因',
  voided_by BIGINT UNSIGNED NULL COMMENT '作废人',
  voided_at DATETIME(3) NULL COMMENT '作废时间',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '更正乐观锁',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '录入时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_late_valid_day (student_id, valid_business_date),
  KEY idx_late_room_date (room_id, status, business_date, id),
  KEY idx_late_report (status, business_date, id),
  CONSTRAINT fk_late_student FOREIGN KEY (student_id) REFERENCES student(id),
  CONSTRAINT fk_late_stay FOREIGN KEY (stay_id) REFERENCES stay_record(id),
  CONSTRAINT fk_late_room FOREIGN KEY (room_id) REFERENCES dorm_room(id),
  CONSTRAINT fk_late_creator FOREIGN KEY (created_by) REFERENCES sys_user(id),
  CONSTRAINT fk_late_editor FOREIGN KEY (updated_by) REFERENCES sys_user(id),
  CONSTRAINT fk_late_voider FOREIGN KEY (voided_by) REFERENCES sys_user(id),
  CONSTRAINT ck_late_location CHECK (JSON_TYPE(location_snapshot) = 'OBJECT'),
  CONSTRAINT ck_late_window CHECK (TIME(return_at) >= '23:00:00' OR TIME(return_at) < '06:00:00'),
  CONSTRAINT ck_late_state CHECK ((status = 'VALID' AND voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR (status = 'VOIDED' AND voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL AND CHAR_LENGTH(TRIM(void_reason)) > 0))
) ENGINE=InnoDB COMMENT='晚归，一名学生每业务日最多一条有效记录';

CREATE TABLE hygiene_check (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '卫生初检主键',
  room_id BIGINT UNSIGNED NOT NULL COMMENT '检查房间',
  location_snapshot JSON NOT NULL COMMENT '初检时地点快照',
  check_at DATETIME(3) NOT NULL COMMENT '初检现场时间',
  check_date DATE GENERATED ALWAYS AS (DATE(check_at)) STORED COMMENT '初检自然日期',
  score TINYINT UNSIGNED NOT NULL COMMENT '初检整数分数0至100',
  problems TEXT NULL COMMENT '低于60分必填的问题描述',
  rectification TEXT NULL COMMENT '低于60分必填的整改要求',
  remark VARCHAR(500) NULL COMMENT '其他说明',
  inspector_id BIGINT UNSIGNED NOT NULL COMMENT '初检人',
  status VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'VALID' COMMENT 'VALID有效 VOIDED作废',
  valid_check_date DATE GENERATED ALWAYS AS (CASE WHEN status = 'VALID' THEN check_date ELSE NULL END) STORED COMMENT '有效初检去重辅助列',
  void_reason VARCHAR(500) NULL COMMENT '作废原因',
  voided_by BIGINT UNSIGNED NULL COMMENT '作废人',
  voided_at DATETIME(3) NULL COMMENT '作废时间',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '初检与复查共用串行化版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '录入时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_hygiene_valid_day (room_id, valid_check_date),
  KEY idx_hygiene_report (status, check_date, id),
  CONSTRAINT fk_hygiene_room FOREIGN KEY (room_id) REFERENCES dorm_room(id),
  CONSTRAINT fk_hygiene_inspector FOREIGN KEY (inspector_id) REFERENCES sys_user(id),
  CONSTRAINT fk_hygiene_voider FOREIGN KEY (voided_by) REFERENCES sys_user(id),
  CONSTRAINT ck_hygiene_location CHECK (JSON_TYPE(location_snapshot) = 'OBJECT'),
  CONSTRAINT ck_hygiene_score CHECK (score <= 100),
  CONSTRAINT ck_hygiene_problem CHECK (score >= 60 OR (problems IS NOT NULL AND CHAR_LENGTH(TRIM(problems)) > 0 AND rectification IS NOT NULL AND CHAR_LENGTH(TRIM(rectification)) > 0)),
  CONSTRAINT ck_hygiene_state CHECK ((status = 'VALID' AND voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR (status = 'VOIDED' AND voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL AND CHAR_LENGTH(TRIM(void_reason)) > 0))
) ENGINE=InnoDB COMMENT='卫生初检，初检结果保留，不被复查覆盖';

CREATE TABLE hygiene_recheck (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '卫生复查主键',
  check_id BIGINT UNSIGNED NOT NULL COMMENT '对应初检',
  recheck_at DATETIME(3) NOT NULL COMMENT '复查时间，不早于初检及上次复查',
  score TINYINT UNSIGNED NOT NULL COMMENT '复查整数分数0至100',
  conclusion VARCHAR(1000) NOT NULL COMMENT '复查结论及未通过时后续整改说明',
  inspector_id BIGINT UNSIGNED NOT NULL COMMENT '复查人',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '录入时间，只追加',
  PRIMARY KEY (id),
  KEY idx_recheck_history (check_id, recheck_at, id),
  CONSTRAINT fk_recheck_initial FOREIGN KEY (check_id) REFERENCES hygiene_check(id),
  CONSTRAINT fk_recheck_inspector FOREIGN KEY (inspector_id) REFERENCES sys_user(id),
  CONSTRAINT ck_recheck_score CHECK (score <= 100),
  CONSTRAINT ck_recheck_conclusion CHECK (CHAR_LENGTH(TRIM(conclusion)) > 0)
) ENGINE=InnoDB COMMENT='卫生历次复查，父初检作废后全部排除业务查询';

CREATE TABLE announcement (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '公告主键',
  title VARCHAR(200) NOT NULL COMMENT '公告标题',
  content MEDIUMTEXT NOT NULL COMMENT '公告正文，展示前过滤危险HTML',
  scope_type VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'ALL全校区 BUILDING单楼栋',
  building_id BIGINT UNSIGNED NULL COMMENT 'BUILDING时必填，ALL时为空',
  status VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DRAFT' COMMENT 'DRAFT PUBLISHED WITHDRAWN',
  created_by BIGINT UNSIGNED NOT NULL COMMENT '创建管理员',
  published_by BIGINT UNSIGNED NULL COMMENT '最近发布管理员',
  published_at DATETIME(3) NULL COMMENT '最近发布时间，列表排序依据',
  withdrawn_by BIGINT UNSIGNED NULL COMMENT '最近下架管理员，重新发布时清空',
  withdrawn_at DATETIME(3) NULL COMMENT '最近下架时间，重新发布时清空',
  version INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '正文或状态更新时间',
  PRIMARY KEY (id),
  KEY idx_notice_list (status, scope_type, published_at, id),
  KEY idx_notice_building (building_id, status, published_at, id),
  CONSTRAINT fk_notice_building FOREIGN KEY (building_id) REFERENCES dorm_building(id),
  CONSTRAINT fk_notice_creator FOREIGN KEY (created_by) REFERENCES sys_user(id),
  CONSTRAINT fk_notice_publisher FOREIGN KEY (published_by) REFERENCES sys_user(id),
  CONSTRAINT fk_notice_withdrawer FOREIGN KEY (withdrawn_by) REFERENCES sys_user(id),
  CONSTRAINT ck_notice_scope CHECK ((scope_type = 'ALL' AND building_id IS NULL) OR (scope_type = 'BUILDING' AND building_id IS NOT NULL)),
  CONSTRAINT ck_notice_required CHECK (CHAR_LENGTH(TRIM(title)) > 0 AND CHAR_LENGTH(TRIM(content)) > 0),
  CONSTRAINT ck_notice_state CHECK (
    (status = 'DRAFT' AND published_by IS NULL AND published_at IS NULL AND withdrawn_by IS NULL AND withdrawn_at IS NULL)
    OR (status = 'PUBLISHED' AND published_by IS NOT NULL AND published_at IS NOT NULL AND withdrawn_by IS NULL AND withdrawn_at IS NULL)
    OR (status = 'WITHDRAWN' AND published_by IS NOT NULL AND published_at IS NOT NULL AND withdrawn_by IS NOT NULL AND withdrawn_at IS NOT NULL AND withdrawn_at >= published_at)
  )
) ENGINE=InnoDB COMMENT='全校区或单楼栋公告，历史发布下架写入操作日志';

CREATE TABLE operation_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '操作审计主键',
  request_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '请求关联号，不是令牌',
  operator_id BIGINT UNSIGNED NULL COMMENT '操作账号，未认证失败可为空',
  module VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'USER RESOURCE STAY REPAIR VISITOR LATE HYGIENE NOTICE',
  action_type VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '具体操作，例如TRANSFER VOID CORRECT',
  target_type VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '白名单业务对象类型，与target_id组合定位',
  target_id BIGINT UNSIGNED NULL COMMENT '对象主键，创建失败时可空，多态对象不设外键',
  building_id BIGINT UNSIGNED NULL COMMENT '业务发生楼栋，跨栋主事件可为空',
  result VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'SUCCESS FAILURE',
  reason VARCHAR(1000) NULL COMMENT '更正作废原因或脱敏失败原因',
  before_data JSON NULL COMMENT '变更前白名单字段，排除密码会话及完整联系方式',
  after_data JSON NULL COMMENT '变更后白名单字段，排除密码会话及完整联系方式',
  operated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '操作时间，只追加',
  PRIMARY KEY (id),
  KEY idx_audit_time (operated_at, id),
  KEY idx_audit_operator (operator_id, operated_at, id),
  KEY idx_audit_action (action_type, operated_at, id),
  KEY idx_audit_target (target_type, target_id, operated_at, id),
  KEY idx_audit_request (request_id),
  CONSTRAINT fk_audit_operator FOREIGN KEY (operator_id) REFERENCES sys_user(id),
  CONSTRAINT fk_audit_building FOREIGN KEY (building_id) REFERENCES dorm_building(id),
  CONSTRAINT ck_audit_result CHECK (result IN ('SUCCESS','FAILURE')),
  CONSTRAINT ck_audit_before CHECK (before_data IS NULL OR JSON_TYPE(before_data) = 'OBJECT'),
  CONSTRAINT ck_audit_after CHECK (after_data IS NULL OR JSON_TYPE(after_data) = 'OBJECT')
) ENGINE=InnoDB COMMENT='关键操作审计，只追加，管理员查询';
