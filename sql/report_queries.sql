-- 只读查询示例。真实接口必须绑定参数并先校验账号、角色与楼栋权限。
USE dormitory_management;
SET SESSION time_zone = '+08:00';
SET @operator_id = 2;
SET @student_id = 1;
SET @start_at = '2026-11-01 00:00:00.000';
SET @end_exclusive = '2026-12-01 00:00:00.000';
SET @start_date = '2026-11-01';
SET @end_date_exclusive = '2026-12-01';

-- Q1 管理员全校区床位快照。无启用床位时百分比为NULL，前端显示“—”。
-- 先汇总启用层级内的床位再计算，避免平均楼栋百分比。
SELECT CURRENT_TIMESTAMP(3) AS snapshot_at, COUNT(*) AS total_beds,
       COUNT(s.id) AS occupied_beds, COUNT(*) - COUNT(s.id) AS available_beds,
       ROUND(100.0 * COUNT(s.id) / NULLIF(COUNT(*),0),1) AS occupancy_rate
FROM dorm_bed b
JOIN dorm_room r ON r.id=b.room_id AND r.status=1
JOIN dorm_building g ON g.id=r.building_id AND g.status=1
LEFT JOIN stay_record s ON s.active_bed_id=b.id
WHERE b.status=1;

-- Q2 宿管楼栋快照，EXISTS避免授权关联造成重复计数。零床位楼栋仍显示。
SELECT g.id AS building_id, g.building_no,
       COUNT(b.id) AS total_beds, COUNT(s.id) AS occupied_beds,
       COUNT(b.id)-COUNT(s.id) AS available_beds,
       ROUND(100.0*COUNT(s.id)/NULLIF(COUNT(b.id),0),1) AS occupancy_rate
FROM dorm_building g
LEFT JOIN dorm_room r ON r.building_id=g.id AND r.status=1 AND g.status=1
LEFT JOIN dorm_bed b ON b.room_id=r.id AND b.status=1
LEFT JOIN stay_record s ON s.active_bed_id=b.id
WHERE EXISTS (SELECT 1 FROM manager_building m JOIN sys_user u ON u.id=m.user_id
              WHERE m.user_id=@operator_id AND m.building_id=g.id AND m.status=1 AND u.role='MANAGER' AND u.status=1)
GROUP BY g.id,g.building_no;

-- Q3 当前资源显示状态，启用容量与总床位保留数分开。
SELECT b.id,b.room_id,b.bed_no,
       CASE WHEN s.id IS NOT NULL THEN 'OCCUPIED'
            WHEN g.status=1 AND r.status=1 AND b.status=1 THEN 'AVAILABLE'
            ELSE 'DISABLED' END AS display_status
FROM dorm_bed b JOIN dorm_room r ON r.id=b.room_id JOIN dorm_building g ON g.id=r.building_id
LEFT JOIN stay_record s ON s.active_bed_id=b.id;

-- Q4 住宿办理量，每笔调宿只计一次并归入目标楼栋。
-- 管理员查询；宿管筛选时必须对归属楼栋增加授权EXISTS。
SELECT x.building_id,l.action_type,COUNT(*) AS action_count
FROM stay_change_log l
JOIN (
  SELECT s.id AS stay_id,r.building_id
  FROM stay_record s JOIN dorm_bed b ON b.id=s.bed_id JOIN dorm_room r ON r.id=b.room_id
) x ON x.stay_id=CASE WHEN l.action_type='CHECKOUT' THEN l.from_stay_id ELSE l.to_stay_id END
WHERE l.operated_at>=@start_at AND l.operated_at<@end_exclusive
GROUP BY x.building_id,l.action_type;

-- Q5 报修提交量与完成量按各自时间独立过滤。
SELECT r.building_id,'SUBMITTED' AS metric,COUNT(*) AS amount
FROM repair_order p JOIN dorm_room r ON r.id=p.room_id
WHERE p.created_at>=@start_at AND p.created_at<@end_exclusive GROUP BY r.building_id
UNION ALL
SELECT r.building_id,'COMPLETED',COUNT(*)
FROM repair_order p JOIN dorm_room r ON r.id=p.room_id
WHERE p.status='COMPLETED' AND p.closed_at>=@start_at AND p.closed_at<@end_exclusive GROUP BY r.building_id;

-- Q6 到访量排除作废；当前在访量不受报表日期筛选影响。
SELECT r.building_id,
       SUM(v.status<>'VOIDED' AND v.arrive_at>=@start_at AND v.arrive_at<@end_exclusive) AS visits_in_period,
       SUM(v.status='VISITING') AS current_visiting
FROM visitor_record v JOIN dorm_room r ON r.id=v.room_id GROUP BY r.building_id;

-- Q7 晚归按业务日期统计，凌晨并入前一天。
SELECT r.building_id,COUNT(*) AS late_count
FROM late_return_record l JOIN dorm_room r ON r.id=l.room_id
WHERE l.status='VALID' AND l.business_date>=@start_date AND l.business_date<@end_date_exclusive GROUP BY r.building_id;

-- Q8 卫生统计只数有效初检，不联结复查行，避免一对多放大。
SELECT r.building_id,COUNT(*) AS initial_count,SUM(h.score>=60) AS passed_count,
       ROUND(100.0*SUM(h.score>=60)/NULLIF(COUNT(*),0),1) AS initial_pass_rate,
       ROUND(AVG(h.score),1) AS initial_average_score
FROM hygiene_check h JOIN dorm_room r ON r.id=h.room_id
WHERE h.status='VALID' AND h.check_date>=@start_date AND h.check_date<@end_date_exclusive GROUP BY r.building_id;

-- Q9 学生本次入住期间、当前房间的有效初检及整改状态。
SELECT h.id,h.room_id,h.check_at,h.score,
       CASE WHEN h.score>=60 THEN 'PASSED'
            WHEN (SELECT z.score FROM hygiene_recheck z WHERE z.check_id=h.id ORDER BY z.recheck_at DESC,z.id DESC LIMIT 1)>=60 THEN 'RECTIFIED'
            ELSE 'PENDING_RECHECK' END AS result_status
FROM stay_record s JOIN dorm_bed b ON b.id=s.bed_id
JOIN hygiene_check h ON h.room_id=b.room_id AND h.check_at>=s.checkin_at AND h.check_at<=CURRENT_TIMESTAMP(3) AND h.status='VALID'
WHERE s.active_student_id=@student_id;

-- Q10 学生公告，身份必须来自会话绑定档案；无当前住宿也能看全校公告。
SELECT a.id,a.title,a.content,a.published_at,a.updated_at
FROM announcement a
WHERE a.status='PUBLISHED' AND
      (a.scope_type='ALL' OR EXISTS (
        SELECT 1 FROM stay_record s JOIN dorm_bed b ON b.id=s.bed_id JOIN dorm_room r ON r.id=b.room_id
        WHERE s.active_student_id=@student_id AND r.building_id=a.building_id))
ORDER BY a.published_at DESC,a.id DESC;

-- Q11 历史时点住宿校验，补录晚归使用半开区间。[checkin, checkout)
SET @event_at = '2026-11-23 01:00:00.000';
SELECT s.id,s.student_id,r.id AS room_id,r.building_id
FROM stay_record s JOIN dorm_bed b ON b.id=s.bed_id JOIN dorm_room r ON r.id=b.room_id
WHERE s.student_id=@student_id AND s.checkin_at<=@event_at
  AND (s.checkout_at IS NULL OR @event_at<s.checkout_at);

-- Q12 数据一致性巡检，正常情况下全部返回空集。
SELECT 'ACTIVE_IN_DISABLED_RESOURCE' AS issue,s.id AS record_id
FROM stay_record s JOIN dorm_bed b ON b.id=s.bed_id JOIN dorm_room r ON r.id=b.room_id JOIN dorm_building g ON g.id=r.building_id
WHERE s.status='ACTIVE' AND (b.status=0 OR r.status=0 OR g.status=0)
UNION ALL
SELECT 'TRANSFER_LINK_MISMATCH',n.id
FROM stay_record n JOIN stay_record o ON o.id=n.transfer_from_id
WHERE o.student_id<>n.student_id OR o.status<>'ENDED' OR o.end_type<>'TRANSFER' OR o.checkout_at<>n.checkin_at
UNION ALL
SELECT 'ACCOUNT_PROFILE_DISABLED',u.id FROM sys_user u JOIN student s ON s.id=u.student_id WHERE u.status=1 AND s.status=0;
