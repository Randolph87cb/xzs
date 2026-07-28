package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.other.PracticeObservationRecord;
import com.mindskip.xzs.repository.ExamPaperAnswerMapper;
import com.mindskip.xzs.service.PracticeObservationService;
import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationRequestVM;
import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationResponseVM;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class PracticeObservationServiceImpl implements PracticeObservationService {

    static final int MIN_IMPROVEMENT_QUESTION_COUNT = 10;
    static final String IMPROVEMENT_RULE =
            "改善学生：当前周期和上一等长周期均至少答 10 题，且当前周期加权正确率更高。";
    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd");
    private static final DateTimeFormatter DATE_TIME_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    private final ExamPaperAnswerMapper examPaperAnswerMapper;

    @Autowired
    public PracticeObservationServiceImpl(ExamPaperAnswerMapper examPaperAnswerMapper) {
        this.examPaperAnswerMapper = examPaperAnswerMapper;
    }

    @Override
    public PracticeObservationResponseVM observe(PracticeObservationRequestVM request, LocalDate today) {
        int days = normalizeDays(request.getDays());
        request.setDays(days);
        request.setStudentName(StringUtils.trimToNull(request.getStudentName()));

        ZoneId zoneId = ZoneId.systemDefault();
        LocalDate currentStart = today.minusDays(days - 1L);
        LocalDate end = today.plusDays(1);
        LocalDate previousStart = currentStart.minusDays(days);
        request.setPreviousStartTime(toDate(previousStart, zoneId));
        request.setCurrentStartTime(toDate(currentStart, zoneId));
        request.setEndTime(toDate(end, zoneId));

        List<PracticeObservationRecord> records = examPaperAnswerMapper.practiceObservation(request);
        return aggregate(records, currentStart, end, previousStart, zoneId);
    }

    PracticeObservationResponseVM aggregate(List<PracticeObservationRecord> records,
                                            LocalDate currentStart,
                                            LocalDate end,
                                            LocalDate previousStart,
                                            ZoneId zoneId) {
        PracticeObservationResponseVM response = new PracticeObservationResponseVM();
        response.setPeriodStart(DATE_FORMAT.format(currentStart));
        response.setPeriodEnd(DATE_FORMAT.format(end.minusDays(1)));
        response.setImprovementRule(IMPROVEMENT_RULE);
        List<String> dates = new ArrayList<>();
        for (LocalDate date = currentStart; date.isBefore(end); date = date.plusDays(1)) {
            dates.add(DATE_FORMAT.format(date));
        }
        response.setDates(dates);

        Map<Integer, StudentAccumulator> accumulators = new LinkedHashMap<>();
        if (records == null) {
            records = Collections.emptyList();
        }
        for (PracticeObservationRecord record : records) {
            StudentAccumulator accumulator = accumulators.get(record.getStudentId());
            if (accumulator == null) {
                accumulator = new StudentAccumulator(record, dates);
                accumulators.put(record.getStudentId(), accumulator);
            }
            if (record.getAnswerId() == null || record.getCreateTime() == null) {
                continue;
            }
            LocalDate answerDate = toLocalDate(record.getCreateTime(), zoneId);
            int questions = safeCount(record.getQuestionCount());
            int correct = Math.min(questions, safeCount(record.getQuestionCorrect()));
            if (!answerDate.isBefore(currentStart) && answerDate.isBefore(end)) {
                accumulator.addCurrent(record, answerDate, questions, correct, zoneId);
            } else if (!answerDate.isBefore(previousStart) && answerDate.isBefore(currentStart)) {
                accumulator.previousQuestions += questions;
                accumulator.previousCorrect += correct;
            }
        }

        PracticeObservationResponseVM.Summary summary = new PracticeObservationResponseVM.Summary();
        int totalQuestions = 0;
        int totalCorrect = 0;
        int activeStudents = 0;
        int improvedStudents = 0;
        List<PracticeObservationResponseVM.Student> students = new ArrayList<>();
        for (StudentAccumulator accumulator : accumulators.values()) {
            PracticeObservationResponseVM.Student student = accumulator.finish();
            students.add(student);
            totalQuestions += student.getQuestionCount();
            totalCorrect += student.getCorrectCount();
            if (student.getQuestionCount() > 0) {
                activeStudents++;
            }
            if (Boolean.TRUE.equals(student.getImproved())) {
                improvedStudents++;
            }
        }
        summary.setActiveStudentCount(activeStudents);
        summary.setTotalQuestionCount(totalQuestions);
        summary.setWeightedAccuracy(accuracy(totalCorrect, totalQuestions));
        summary.setImprovedStudentCount(improvedStudents);
        response.setSummary(summary);
        response.setStudents(students);
        return response;
    }

    private int normalizeDays(Integer days) {
        if (days == null) {
            return 7;
        }
        return days == 7 || days == 14 || days == 30 ? days : 7;
    }

    private static Date toDate(LocalDate date, ZoneId zoneId) {
        return Date.from(date.atStartOfDay(zoneId).toInstant());
    }

    private static LocalDate toLocalDate(Date date, ZoneId zoneId) {
        return date.toInstant().atZone(zoneId).toLocalDate();
    }

    private static int safeCount(Integer value) {
        return value == null || value < 0 ? 0 : value;
    }

    private static Double accuracy(int correct, int questions) {
        if (questions <= 0) {
            return null;
        }
        return Math.round(correct * 1000.0 / questions) / 10.0;
    }

    private static class StudentAccumulator {
        private final PracticeObservationResponseVM.Student student = new PracticeObservationResponseVM.Student();
        private final Map<String, PracticeObservationResponseVM.Day> dayMap = new LinkedHashMap<>();
        private int previousQuestions;
        private int previousCorrect;
        private int activeDays;

        StudentAccumulator(PracticeObservationRecord record, List<String> dates) {
            student.setId(record.getStudentId());
            student.setUserName(record.getUserName());
            student.setName(StringUtils.defaultIfBlank(record.getRealName(), record.getUserName()));
            student.setImagePath(record.getImagePath());
            student.setClassId(record.getClassId());
            student.setClassName(record.getClassName());
            student.setGradeLevel(record.getGradeLevel());
            student.setDirectionLabel(directionLabel(record));
            for (String date : dates) {
                dayMap.put(date, new PracticeObservationResponseVM.Day(date));
            }
        }

        void addCurrent(PracticeObservationRecord record, LocalDate answerDate, int questions, int correct, ZoneId zoneId) {
            student.setQuestionCount(student.getQuestionCount() + questions);
            student.setCorrectCount(student.getCorrectCount() + correct);
            PracticeObservationResponseVM.Day day = dayMap.get(DATE_FORMAT.format(answerDate));
            if (day != null) {
                if (day.getQuestionCount() == 0 && questions > 0) {
                    activeDays++;
                }
                day.setQuestionCount(day.getQuestionCount() + questions);
                day.setCorrectCount(day.getCorrectCount() + correct);
            }
            PracticeObservationResponseVM.Practice practice = new PracticeObservationResponseVM.Practice();
            practice.setId(record.getAnswerId());
            practice.setPaperName(record.getPaperName());
            practice.setCreateTime(DATE_TIME_FORMAT.format(record.getCreateTime().toInstant().atZone(zoneId)));
            practice.setQuestionCount(questions);
            practice.setCorrectCount(correct);
            practice.setWeightedAccuracy(accuracy(correct, questions));
            student.getRecentPractices().add(practice);
        }

        PracticeObservationResponseVM.Student finish() {
            student.setWeightedAccuracy(accuracy(student.getCorrectCount(), student.getQuestionCount()));
            for (PracticeObservationResponseVM.Day day : dayMap.values()) {
                day.setWeightedAccuracy(accuracy(day.getCorrectCount(), day.getQuestionCount()));
            }
            student.setDays(new ArrayList<>(dayMap.values()));
            student.getRecentPractices().sort(Comparator.comparing(PracticeObservationResponseVM.Practice::getCreateTime).reversed());
            if (student.getRecentPractices().size() > 3) {
                student.setRecentPractices(new ArrayList<>(student.getRecentPractices().subList(0, 3)));
            }
            boolean comparable = student.getQuestionCount() >= MIN_IMPROVEMENT_QUESTION_COUNT
                    && previousQuestions >= MIN_IMPROVEMENT_QUESTION_COUNT;
            if (comparable) {
                student.setImproved(
                        student.getCorrectCount() * (long) previousQuestions > previousCorrect * (long) student.getQuestionCount());
            }
            student.setAttentionText(attentionText(student, activeDays));
            return student;
        }

        private String attentionText(PracticeObservationResponseVM.Student student, int activeDays) {
            if (student.getQuestionCount() == 0) {
                return "本周期还没有练习记录，可在方便时了解一下近期安排。";
            }
            if (student.getWeightedAccuracy() != null && student.getQuestionCount() >= 10
                    && student.getWeightedAccuracy() < 60.0) {
                return "近期正确率仍有提升空间，建议结合错题温和跟进。";
            }
            if (activeDays <= 1) {
                return "练习集中在少数日期，可了解是否需要更均匀的节奏。";
            }
            if (Boolean.TRUE.equals(student.getImproved())) {
                return "近期正确率较前一周期有所提升。";
            }
            return "练习节奏平稳，可继续观察。";
        }

        private static String directionLabel(PracticeObservationRecord record) {
            List<String> parts = new ArrayList<>();
            if (StringUtils.isNotBlank(record.getTargetSubjectName())) {
                parts.add(record.getTargetSubjectName());
            }
            if (StringUtils.isNotBlank(record.getClassName())) {
                parts.add(record.getClassName());
            } else if (record.getGradeLevel() != null) {
                parts.add(record.getGradeLevel() + " 级");
            }
            return parts.isEmpty() ? "未设置备考方向" : StringUtils.join(parts, " · ");
        }
    }
}
