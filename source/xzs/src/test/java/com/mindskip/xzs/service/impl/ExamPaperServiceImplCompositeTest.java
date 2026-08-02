package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.QuestionGroup;
import com.mindskip.xzs.domain.SmartTrainingConfig;
import com.mindskip.xzs.domain.exam.ExamPaperItemObject;
import com.mindskip.xzs.domain.exam.QuestionSelectionUnit;
import com.mindskip.xzs.repository.ExamPaperMapper;
import com.mindskip.xzs.repository.QuestionGroupMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SmartTrainingConfigService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.viewmodel.admin.smarttraining.SmartTrainingRuleVM;
import org.junit.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class ExamPaperServiceImplCompositeTest {
    @Test
    public void smartTrainingExpandsOnlyWholeGroupsAndHitsFinalQuestionCount() {
        QuestionMapper questionMapper = mock(QuestionMapper.class);
        QuestionGroupMapper groupMapper = mock(QuestionGroupMapper.class);
        SmartTrainingConfigService configService = mock(SmartTrainingConfigService.class);
        Question independent = question(1, null, null);
        Question child1 = question(2, 9, 1);
        Question child2 = question(3, 9, 2);
        QuestionGroup group = new QuestionGroup();
        group.setId(9); group.setSubjectId(9); group.setKnowledgePoint("k");
        SmartTrainingConfig config = new SmartTrainingConfig();
        config.setQuestionCount(3); config.setRuleJson("");
        when(configService.selectBySubjectId(9)).thenReturn(config);
        when(questionMapper.selectActiveIndependentBySubjectId(9)).thenReturn(Arrays.asList(independent));
        when(groupMapper.selectActiveBySubjectId(9)).thenReturn(Arrays.asList(group));
        when(questionMapper.selectByQuestionGroupIds(Arrays.asList(9))).thenReturn(Arrays.asList(child1, child2));
        ExamPaperServiceImpl service = new ExamPaperServiceImpl(
                mock(ExamPaperMapper.class), questionMapper, mock(TextContentService.class), mock(QuestionService.class),
                mock(SubjectService.class), configService, mock(JdbcTemplate.class), groupMapper);

        List<QuestionSelectionUnit> selected = service.selectSmartTrainingUnits(9, new Random(3));

        assertEquals(3, selected.stream().mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
        assertTrue(selected.stream().anyMatch(unit -> ExamPaperItemObject.QUESTION_GROUP.equals(unit.getType())
                && unit.getQuestions().size() == 2));
    }

    @Test
    public void smartTrainingWeightsInfluenceFeasibleRemainingAllocation() {
        QuestionMapper questionMapper = mock(QuestionMapper.class);
        QuestionGroupMapper groupMapper = mock(QuestionGroupMapper.class);
        SmartTrainingConfigService configService = mock(SmartTrainingConfigService.class);
        List<Question> independentQuestions = Arrays.asList(
                question(1, "high"), question(2, "high"), question(3, "high"),
                question(4, "low"), question(5, "low"), question(6, "low"));
        when(questionMapper.selectActiveIndependentBySubjectId(9)).thenReturn(independentQuestions);
        when(groupMapper.selectActiveBySubjectId(9)).thenReturn(Collections.emptyList());

        SmartTrainingConfig config = new SmartTrainingConfig();
        config.setQuestionCount(3);
        when(configService.selectBySubjectId(9)).thenReturn(config);
        ExamPaperServiceImpl service = new ExamPaperServiceImpl(
                mock(ExamPaperMapper.class), questionMapper, mock(TextContentService.class), mock(QuestionService.class),
                mock(SubjectService.class), configService, mock(JdbcTemplate.class), groupMapper);

        config.setRuleJson(JsonUtil.toJsonStr(Arrays.asList(rule("high", 100), rule("low", 1))));
        List<QuestionSelectionUnit> highWeighted = service.selectSmartTrainingUnits(9, new Random(1));
        assertEquals(3, highWeighted.stream().mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
        assertEquals(3, highWeighted.stream().filter(unit -> "high".equals(unit.getKnowledgePoint()))
                .mapToInt(QuestionSelectionUnit::getQuestionCount).sum());

        config.setRuleJson(JsonUtil.toJsonStr(Arrays.asList(rule("high", 1), rule("low", 100))));
        List<QuestionSelectionUnit> lowWeighted = service.selectSmartTrainingUnits(9, new Random(1));
        assertEquals(3, lowWeighted.stream().mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
        assertEquals(3, lowWeighted.stream().filter(unit -> "low".equals(unit.getKnowledgePoint()))
                .mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
    }

    @Test
    public void legacyFixedCountsRemainExactForIndependentQuestionRules() {
        QuestionMapper questionMapper = mock(QuestionMapper.class);
        QuestionGroupMapper groupMapper = mock(QuestionGroupMapper.class);
        SmartTrainingConfigService configService = mock(SmartTrainingConfigService.class);
        when(questionMapper.selectActiveIndependentBySubjectId(9)).thenReturn(Arrays.asList(
                question(1, "GESP1级/A"), question(2, "GESP1级/A"), question(3, "GESP1级/A"),
                question(4, "GESP1级/B"), question(5, "GESP1级/B")));
        when(groupMapper.selectActiveBySubjectId(9)).thenReturn(Collections.emptyList());

        SmartTrainingRuleVM firstRule = rule("GESP1级/A", 100);
        firstRule.setMinCount(null);
        firstRule.setMaxCount(null);
        firstRule.setQuestionCount(2);
        SmartTrainingRuleVM secondRule = rule("GESP1级/B", 1);
        secondRule.setMinCount(null);
        secondRule.setMaxCount(null);
        secondRule.setQuestionCount(1);
        SmartTrainingConfig config = new SmartTrainingConfig();
        config.setQuestionCount(3);
        config.setRuleJson(JsonUtil.toJsonStr(Arrays.asList(firstRule, secondRule)));
        when(configService.selectBySubjectId(9)).thenReturn(config);
        ExamPaperServiceImpl service = new ExamPaperServiceImpl(
                mock(ExamPaperMapper.class), questionMapper, mock(TextContentService.class), mock(QuestionService.class),
                mock(SubjectService.class), configService, mock(JdbcTemplate.class), groupMapper);

        List<QuestionSelectionUnit> selected = service.selectSmartTrainingUnits(9, new Random(4));

        assertEquals(3, selected.stream().mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
        assertEquals(2, selected.stream().filter(unit -> "GESP1级/A".equals(unit.getKnowledgePoint()))
                .mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
        assertEquals(1, selected.stream().filter(unit -> "GESP1级/B".equals(unit.getKnowledgePoint()))
                .mapToInt(QuestionSelectionUnit::getQuestionCount).sum());
    }

    private SmartTrainingRuleVM rule(String knowledgePoint, int weight) {
        SmartTrainingRuleVM rule = new SmartTrainingRuleVM();
        rule.setKnowledgePoint(knowledgePoint);
        rule.setMinCount(0);
        rule.setMaxCount(3);
        rule.setWeight(weight);
        rule.setEnabled(true);
        return rule;
    }

    private Question question(int id, String knowledgePoint) {
        Question question = question(id, null, null);
        question.setKnowledgePoint(knowledgePoint);
        return question;
    }

    private Question question(int id, Integer groupId, Integer order) {
        Question q = new Question(); q.setId(id); q.setSubjectId(9); q.setQuestionGroupId(groupId);
        q.setGroupItemOrder(order); q.setKnowledgePoint("k"); q.setStatus(1); q.setDeleted(false); q.setScore(10); return q;
    }
}
