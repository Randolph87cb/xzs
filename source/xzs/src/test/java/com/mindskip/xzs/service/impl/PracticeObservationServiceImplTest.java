package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.other.PracticeObservationRecord;
import com.mindskip.xzs.repository.ExamPaperAnswerMapper;
import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationResponseVM;
import org.junit.Test;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;

public class PracticeObservationServiceImplTest {

    private final ZoneId zoneId = ZoneId.systemDefault();
    private final PracticeObservationServiceImpl service =
            new PracticeObservationServiceImpl(mock(ExamPaperAnswerMapper.class));

    @Test
    public void aggregateUsesQuestionWeightedAccuracyAndNonOverlappingPeriods() {
        LocalDate currentStart = LocalDate.of(2026, 7, 22);
        LocalDate end = LocalDate.of(2026, 7, 29);
        LocalDate previousStart = LocalDate.of(2026, 7, 15);

        PracticeObservationResponseVM response = service.aggregate(Arrays.asList(
                record(1, "小明", currentStart, 9, 10),
                record(1, "小明", currentStart.plusDays(1), 0, 1),
                record(1, "小明", previousStart, 8, 10),
                record(2, "小红", currentStart.plusDays(2), 1, 1)
        ), currentStart, end, previousStart, zoneId);

        assertEquals(Integer.valueOf(11), response.getStudents().get(0).getQuestionCount());
        assertEquals(Double.valueOf(81.8), response.getStudents().get(0).getWeightedAccuracy());
        assertEquals(Integer.valueOf(12), response.getSummary().getTotalQuestionCount());
        assertEquals(Double.valueOf(83.3), response.getSummary().getWeightedAccuracy());
        assertEquals("/upload/student1.png", response.getStudents().get(0).getImagePath());
        assertTrue(response.getStudents().get(0).getImproved());
        assertEquals(Integer.valueOf(1), response.getSummary().getImprovedStudentCount());
    }

    @Test
    public void improvementRequiresTenQuestionsInBothPeriods() {
        LocalDate currentStart = LocalDate.of(2026, 7, 22);
        LocalDate end = LocalDate.of(2026, 7, 29);
        LocalDate previousStart = LocalDate.of(2026, 7, 15);

        PracticeObservationResponseVM response = service.aggregate(Arrays.asList(
                record(1, "样本不足", currentStart, 9, 9),
                record(1, "样本不足", previousStart, 0, 9),
                record(2, "没有改善", currentStart, 7, 10),
                record(2, "没有改善", previousStart, 8, 10)
        ), currentStart, end, previousStart, zoneId);

        assertNull(response.getStudents().get(0).getImproved());
        assertFalse(response.getStudents().get(1).getImproved());
        assertEquals(Integer.valueOf(0), response.getSummary().getImprovedStudentCount());
        assertTrue(response.getImprovementRule().contains("均至少答 10 题"));
    }

    @Test
    public void studentWithoutPracticeKeepsBlankDaysAndNullAccuracy() {
        LocalDate currentStart = LocalDate.of(2026, 7, 22);
        LocalDate end = LocalDate.of(2026, 7, 29);
        PracticeObservationRecord student = record(1, "暂无练习", null, null, null);
        student.setAnswerId(null);
        student.setCreateTime(null);
        student.setImagePath(null);

        PracticeObservationResponseVM response = service.aggregate(
                Collections.singletonList(student),
                currentStart,
                end,
                currentStart.minusDays(7),
                zoneId);

        assertEquals(Integer.valueOf(0), response.getSummary().getActiveStudentCount());
        assertNull(response.getSummary().getWeightedAccuracy());
        assertNull(response.getStudents().get(0).getImagePath());
        assertEquals(7, response.getStudents().get(0).getDays().size());
        assertTrue(response.getStudents().get(0).getDays().stream()
                .allMatch(day -> day.getQuestionCount() == 0 && day.getWeightedAccuracy() == null));
        assertTrue(response.getStudents().get(0).getAttentionText().contains("还没有练习记录"));
    }

    private PracticeObservationRecord record(Integer studentId, String name, LocalDate date,
                                             Integer correct, Integer questions) {
        PracticeObservationRecord record = new PracticeObservationRecord();
        record.setStudentId(studentId);
        record.setUserName("student" + studentId);
        record.setRealName(name);
        record.setImagePath("/upload/student" + studentId + ".png");
        record.setClassId(1);
        record.setClassName("GESP 4级");
        record.setAnswerId(date == null ? null : studentId * 100 + date.getDayOfMonth());
        record.setPaperName("练习卷");
        record.setQuestionCorrect(correct);
        record.setQuestionCount(questions);
        if (date != null) {
            record.setCreateTime(Date.from(date.atTime(12, 0).atZone(zoneId).toInstant()));
        }
        return record;
    }
}
