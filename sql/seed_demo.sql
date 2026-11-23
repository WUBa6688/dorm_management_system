-- 仅导入新建空库；全部姓名、联系方式和业务记录均为虚构演示数据。
-- 在同一连接中先 SET @demo_password_hash = '用后端BCrypt生成的60字符哈希';
-- 未设置有效哈希时，账号写入失败，整个未提交事务回滚；不提供固定演示口令。
USE dormitory_management;
SET NAMES utf8mb4;
SET SESSION time_zone = '+08:00';
-- 用异常处理器保证交互SOURCE继续读文件时也不会提交半套演示数据。
-- 此辅助过程仅在导入期间存在，成功后删除；失败后的残留过程见设计说明。
DELIMITER $$
CREATE PROCEDURE seed_dorm_demo()
BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
  ROLLBACK;
  RESIGNAL;
END;
IF @demo_password_hash IS NULL OR CHAR_LENGTH(@demo_password_hash) <> 60
   OR LEFT(@demo_password_hash,4) NOT IN ('$2a$','$2b$','$2y$') THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Set @demo_password_hash to a generated 60-character BCrypt hash';
END IF;
START TRANSACTION;

INSERT INTO student (id, student_no, name, gender, college, major, class_name, phone)
SELECT n, CONCAT('202600', LPAD(n, 2, '0')), CONCAT('演示学生', LPAD(n, 2, '0')),
       IF(MOD(n,2)=1,'M','F'), '演示学院', '软件工程', '软件2601', NULL
FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
      UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
      UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12
      UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15 UNION ALL SELECT 16
      UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20) numbers;

INSERT INTO sys_user (id, username, password_hash, role, display_name)
VALUES (1,'admin',@demo_password_hash,'ADMIN','演示管理员'),
       (2,'manager_a',@demo_password_hash,'MANAGER','一号楼宿管'),
       (3,'manager_b',@demo_password_hash,'MANAGER','二号楼宿管'),
       (4,'manager_c',@demo_password_hash,'MANAGER','三号楼宿管');
INSERT INTO sys_user (id, username, password_hash, role, student_id, display_name)
SELECT 100 + id, CONCAT('student_',LPAD(id,2,'0')), @demo_password_hash, 'STUDENT', id, name FROM student;

INSERT INTO dorm_building (id,building_no,building_name,floors,gender_limit)
VALUES (1,'B01','演示一号楼',6,'M'),(2,'B02','演示二号楼',6,'F'),(3,'B03','演示三号楼',6,'ALL');
INSERT INTO manager_building (user_id,building_id,granted_by,granted_at)
VALUES (2,1,1,'2026-11-01 08:00:00'),(3,2,1,'2026-11-01 08:00:00'),(4,3,1,'2026-11-01 08:00:00');
INSERT INTO dorm_room (id,building_id,room_no,floor_no,gender_limit)
VALUES (1,1,'101',1,'M'),(2,1,'102',1,'M'),(3,2,'101',1,'F'),
       (4,2,'102',1,'F'),(5,3,'101',1,'ALL'),(6,3,'102',1,'ALL');
INSERT INTO dorm_bed (id,room_id,bed_no,status)
SELECT (r.id-1)*4+n, r.id, CAST(n AS CHAR), IF(r.id=6 AND n=4,0,1)
FROM dorm_room r CROSS JOIN (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) beds;

INSERT INTO stay_record (id,student_id,bed_id,location_snapshot,checkin_at,checkin_by)
SELECT x.n,x.student_id,x.bed_id,
       JSON_OBJECT('buildingId',g.id,'buildingNo',g.building_no,'buildingName',g.building_name,'roomId',r.id,'roomNo',r.room_no,'bedId',b.id,'bedNo',b.bed_no),
       '2026-11-01 09:00:00',1
FROM (SELECT 1 n,1 student_id,1 bed_id UNION ALL SELECT 2,2,9
      UNION ALL SELECT 3,3,2 UNION ALL SELECT 4,4,10
      UNION ALL SELECT 5,5,17 UNION ALL SELECT 6,6,18
      UNION ALL SELECT 7,7,3 UNION ALL SELECT 8,8,11) x
JOIN dorm_bed b ON b.id=x.bed_id JOIN dorm_room r ON r.id=b.room_id JOIN dorm_building g ON g.id=r.building_id;
INSERT INTO stay_change_log (operation_no,student_id,action_type,to_stay_id,operator_id,operated_at)
SELECT UUID(),student_id,'CHECKIN',id,1,checkin_at FROM stay_record;

UPDATE stay_record SET status='ENDED',checkout_at='2026-11-15 10:00:00',end_type='CHECKOUT',end_reason='演示退宿',checkout_by=1,version=version+1 WHERE id=7;
INSERT INTO stay_change_log (operation_no,student_id,action_type,from_stay_id,operator_id,operated_at,remark)
VALUES (UUID(),7,'CHECKOUT',7,1,'2026-11-15 10:00:00','演示退宿');
UPDATE stay_record SET status='ENDED',checkout_at='2026-11-10 10:00:00',end_type='TRANSFER',end_reason='演示同栋调宿',checkout_by=1,version=version+1 WHERE id=8;
INSERT INTO stay_record (id,student_id,bed_id,transfer_from_id,location_snapshot,checkin_at,checkin_by)
SELECT 9,8,b.id,8,JSON_OBJECT('buildingId',g.id,'buildingNo',g.building_no,'buildingName',g.building_name,'roomId',r.id,'roomNo',r.room_no,'bedId',b.id,'bedNo',b.bed_no),
       '2026-11-10 10:00:00',1
FROM dorm_bed b JOIN dorm_room r ON r.id=b.room_id JOIN dorm_building g ON g.id=r.building_id WHERE b.id=12;
INSERT INTO stay_change_log (operation_no,student_id,action_type,from_stay_id,to_stay_id,operator_id,operated_at,remark)
VALUES (UUID(),8,'TRANSFER',8,9,1,'2026-11-10 10:00:00','演示同栋调宿');

SET @room1_snapshot = JSON_OBJECT('buildingId',1,'buildingNo','B01','buildingName','演示一号楼','roomId',1,'roomNo','101');
SET @room3_snapshot = JSON_OBJECT('buildingId',2,'buildingNo','B02','buildingName','演示二号楼','roomId',3,'roomNo','101');
SET @room5_snapshot = JSON_OBJECT('buildingId',3,'buildingNo','B03','buildingName','演示三号楼','roomId',5,'roomNo','101');
INSERT INTO repair_order (id,order_no,student_id,stay_id,room_id,location_snapshot,category,title,description,contact_phone,status,accepted_by,accepted_at,closed_by,closed_at,close_remark,created_at)
VALUES (1,'DEMO-R001',1,1,1,@room1_snapshot,'WATER','演示水龙头漏水','演示故障描述','DEMO-PHONE','PENDING',NULL,NULL,NULL,NULL,NULL,'2026-11-20 09:00:00'),
       (2,'DEMO-R002',1,1,1,@room1_snapshot,'ELECTRIC','演示灯具故障','演示故障描述','DEMO-PHONE','PROCESSING',2,'2026-11-20 10:00:00',NULL,NULL,NULL,'2026-11-20 09:00:00'),
       (3,'DEMO-R003',1,1,1,@room1_snapshot,'FURNITURE','演示桌椅维修','演示故障描述','DEMO-PHONE','COMPLETED',2,'2026-11-20 10:00:00',2,'2026-11-21 10:00:00','演示维修完成','2026-11-20 09:00:00'),
       (4,'DEMO-R004',1,1,1,@room1_snapshot,'OTHER','演示撤销报修','演示故障描述','DEMO-PHONE','CANCELLED',NULL,NULL,101,'2026-11-20 09:30:00','演示学生撤销','2026-11-20 09:00:00'),
       (5,'DEMO-R005',1,1,1,@room1_snapshot,'OTHER','演示退回报修','演示故障描述','DEMO-PHONE','REJECTED',NULL,NULL,2,'2026-11-20 09:30:00','演示信息不完整退回','2026-11-20 09:00:00');
INSERT INTO visitor_record (id,student_id,stay_id,room_id,location_snapshot,visitor_name,visitor_phone,purpose,arrive_at,registered_by)
VALUES (1,1,1,1,@room1_snapshot,'演示访客甲','DEMO-PHONE','演示探访','2026-11-23 09:00:00',2),
       (2,2,2,3,@room3_snapshot,'演示访客乙','DEMO-PHONE','演示探访','2026-11-22 09:00:00',3),
       (3,1,1,1,@room1_snapshot,'演示误登访客','DEMO-PHONE','演示误登','2026-11-22 09:00:00',2);
UPDATE visitor_record SET status='LEFT',leave_at='2026-11-22 10:00:00',left_by=3 WHERE id=2;
UPDATE visitor_record SET status='VOIDED',void_reason='演示误登作废',voided_by=2,voided_at='2026-11-22 09:10:00' WHERE id=3;
INSERT INTO late_return_record (id,student_id,stay_id,room_id,location_snapshot,return_at,reason,created_by,updated_by)
VALUES (1,1,1,1,@room1_snapshot,'2026-11-22 23:15:00','演示晚归',2,2),
       (2,2,2,3,@room3_snapshot,'2026-11-23 01:00:00','演示凌晨归寝',3,3);
INSERT INTO late_return_record (id,student_id,stay_id,room_id,location_snapshot,return_at,reason,created_by,updated_by,status,void_reason,voided_by,voided_at)
VALUES (3,1,1,1,@room1_snapshot,'2026-11-22 23:05:00','演示误登',2,2,'VOIDED','演示重复记录作废',2,'2026-11-23 08:00:00');
INSERT INTO hygiene_check (id,room_id,location_snapshot,check_at,score,problems,rectification,inspector_id)
VALUES (1,1,@room1_snapshot,'2026-11-20 10:00:00',59,'演示地面未清理','演示要求清扫',2),
       (2,3,@room3_snapshot,'2026-11-20 10:00:00',90,NULL,NULL,3),
       (3,5,@room5_snapshot,'2026-11-20 10:00:00',65,NULL,NULL,4);
INSERT INTO hygiene_recheck (id,check_id,recheck_at,score,conclusion,inspector_id)
VALUES (1,1,'2026-11-21 10:00:00',55,'演示整改未完成，继续清扫',2),
       (2,1,'2026-11-22 10:00:00',60,'演示整改通过',2);
INSERT INTO announcement (id,title,content,scope_type,building_id,status,created_by,published_by,published_at,withdrawn_by,withdrawn_at)
VALUES (1,'演示全校公告','演示全校公告正文','ALL',NULL,'PUBLISHED',1,1,'2026-11-20 09:00:00',NULL,NULL),
       (2,'演示一号楼公告','仅一号楼当前住户和授权宿管可见','BUILDING',1,'PUBLISHED',1,1,'2026-11-21 09:00:00',NULL,NULL),
       (3,'演示草稿','草稿对学生不可见','ALL',NULL,'DRAFT',1,NULL,NULL,NULL,NULL),
       (4,'演示下架公告','下架公告对学生不可见','ALL',NULL,'WITHDRAWN',1,1,'2026-11-19 09:00:00',1,'2026-11-20 09:00:00');
INSERT INTO operation_log (request_id,operator_id,module,action_type,target_type,target_id,result,reason,after_data,operated_at)
SELECT CONCAT('demo-stay-',id),operator_id,'STAY',action_type,'stay_change_log',id,'SUCCESS',remark,
       JSON_OBJECT('studentId',student_id,'fromStayId',from_stay_id,'toStayId',to_stay_id),operated_at FROM stay_change_log;
INSERT INTO operation_log (request_id,operator_id,module,action_type,target_type,target_id,building_id,result,reason,before_data,after_data,operated_at)
VALUES ('demo-visitor-void',2,'VISITOR','VOID','visitor_record',3,1,'SUCCESS','演示误登作废',JSON_OBJECT('status','VISITING'),JSON_OBJECT('status','VOIDED'),'2026-11-22 09:10:00');
COMMIT;
END$$
DELIMITER ;
CALL seed_dorm_demo();
DROP PROCEDURE seed_dorm_demo;
