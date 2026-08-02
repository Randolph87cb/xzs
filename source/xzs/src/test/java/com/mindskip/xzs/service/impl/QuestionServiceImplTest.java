package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.repository.QuestionGroupMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class QuestionServiceImplTest {
    private QuestionMapper questionMapper;
    private TextContentService textContentService;
    private SubjectService subjectService;
    private QuestionServiceImpl service;

    @Before
    public void setUp() {
        questionMapper = mock(QuestionMapper.class);
        textContentService = mock(TextContentService.class);
        subjectService = mock(SubjectService.class);
        service = new QuestionServiceImpl(questionMapper, textContentService, subjectService,
                mock(JdbcTemplate.class), mock(QuestionGroupMapper.class));
    }

    @Test
    public void ordinaryUpdateRejectsGroupedChildBeforeCrossSubjectMutation() {
        Question groupedChild = question(100, 9, 8);
        when(questionMapper.selectByPrimaryKey(100)).thenReturn(groupedChild);

        try {
            service.updateFullQuestion(model(100, 10));
            fail("Expected grouped child update to be rejected");
        } catch (IllegalArgumentException exception) {
            assertEquals("题组子题请在题组中编辑", exception.getMessage());
        }

        verify(subjectService, never()).levelBySubjectId(any());
        verify(questionMapper, never()).updateByPrimaryKeySelective(any(Question.class));
    }

    @Test
    public void groupUpdateUsesControlledPathForItsOwnChild() {
        Question groupedChild = question(100, 9, 8);
        groupedChild.setInfoTextContentId(80);
        TextContent content = new TextContent();
        when(questionMapper.selectByPrimaryKey(100)).thenReturn(groupedChild);
        when(subjectService.levelBySubjectId(9)).thenReturn(9);
        when(textContentService.selectById(80)).thenReturn(content);

        Question updated = service.updateFullQuestionFromGroup(model(100, 9), 8);

        assertEquals(Integer.valueOf(8), updated.getQuestionGroupId());
        assertEquals(Integer.valueOf(9), updated.getSubjectId());
        verify(questionMapper).updateByPrimaryKeySelective(groupedChild);
        verify(textContentService).updateByIdFilter(content);
    }

    private Question question(Integer id, Integer subjectId, Integer groupId) {
        Question question = new Question();
        question.setId(id);
        question.setSubjectId(subjectId);
        question.setQuestionType(1);
        question.setQuestionGroupId(groupId);
        question.setDeleted(false);
        return question;
    }

    private QuestionEditRequestVM model(Integer id, Integer subjectId) {
        QuestionEditRequestVM model = new QuestionEditRequestVM();
        model.setId(id);
        model.setSubjectId(subjectId);
        model.setScore("5");
        model.setDifficult(1);
        model.setKnowledgePoint("综合");
        model.setCorrect("A");
        model.setTitle("题干");
        model.setAnalyze("解析");
        model.setItems(Collections.emptyList());
        return model;
    }
}
