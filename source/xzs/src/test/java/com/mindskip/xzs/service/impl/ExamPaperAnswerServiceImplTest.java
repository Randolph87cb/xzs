package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.ExamPaper;
import com.mindskip.xzs.domain.ExamPaperAnswerInfo;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TaskExam;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.QuestionTypeEnum;
import com.mindskip.xzs.repository.ExamPaperAnswerMapper;
import com.mindskip.xzs.repository.ExamPaperMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.repository.TaskExamCustomerAnswerMapper;
import com.mindskip.xzs.repository.TaskExamMapper;
import com.mindskip.xzs.service.ExamPaperQuestionCustomerAnswerService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitItemVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitVM;
import org.junit.Before;
import org.junit.Test;

import java.util.Arrays;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class ExamPaperAnswerServiceImplTest {

    private ExamPaperMapper examPaperMapper;
    private TextContentService textContentService;
    private QuestionMapper questionMapper;
    private TaskExamCustomerAnswerMapper taskExamCustomerAnswerMapper;
    private TaskExamMapper taskExamMapper;
    private ExamPaperAnswerServiceImpl service;

    @Before
    public void setUp() {
        examPaperMapper = mock(ExamPaperMapper.class);
        textContentService = mock(TextContentService.class);
        questionMapper = mock(QuestionMapper.class);
        taskExamCustomerAnswerMapper = mock(TaskExamCustomerAnswerMapper.class);
        taskExamMapper = mock(TaskExamMapper.class);
        service = new ExamPaperAnswerServiceImpl(
                mock(ExamPaperAnswerMapper.class),
                examPaperMapper,
                textContentService,
                questionMapper,
                mock(ExamPaperQuestionCustomerAnswerService.class),
                taskExamCustomerAnswerMapper,
                taskExamMapper);
    }

    @Test
    public void calculateExamPaperAnswerAllowsRepeatedTaskPaperSubmission() {
        when(examPaperMapper.selectByPrimaryKey(101)).thenReturn(examPaper());
        when(taskExamMapper.selectByPrimaryKey(8)).thenReturn(taskExam());
        when(textContentService.selectById(301)).thenReturn(new TextContent("[{\"name\":\"一\",\"questionItems\":[{\"id\":1001,\"itemOrder\":1}]}]", null));
        when(textContentService.selectById(401)).thenReturn(new TextContent("[{\"examPaperId\":101,\"examPaperName\":\"任务卷\",\"itemOrder\":1}]", null));
        when(questionMapper.selectByIds(Arrays.asList(1001))).thenReturn(Arrays.asList(question()));

        ExamPaperAnswerInfo result = service.calculateExamPaperAnswer(submit(), user());

        assertNotNull(result);
        assertEquals(Integer.valueOf(101), result.getExamPaperAnswer().getExamPaperId());
        assertEquals(Integer.valueOf(8), result.getExamPaperAnswer().getTaskExamId());
        assertEquals(1, result.getExamPaperQuestionCustomerAnswers().size());
        verify(taskExamCustomerAnswerMapper, never()).getByTUid(8, 7);
    }

    private ExamPaper examPaper() {
        ExamPaper paper = new ExamPaper();
        paper.setId(101);
        paper.setName("任务卷");
        paper.setSubjectId(1);
        paper.setPaperType(6);
        paper.setScore(10);
        paper.setQuestionCount(1);
        paper.setFrameTextContentId(301);
        return paper;
    }

    private TaskExam taskExam() {
        TaskExam taskExam = new TaskExam();
        taskExam.setId(8);
        taskExam.setClassId(2);
        taskExam.setFrameTextContentId(401);
        taskExam.setDeleted(false);
        return taskExam;
    }

    private Question question() {
        Question question = new Question();
        question.setId(1001);
        question.setQuestionType(QuestionTypeEnum.SingleChoice.getCode());
        question.setSubjectId(1);
        question.setScore(10);
        question.setCorrect("A");
        return question;
    }

    private ExamPaperSubmitVM submit() {
        ExamPaperSubmitItemVM item = new ExamPaperSubmitItemVM();
        item.setQuestionId(1001);
        item.setContent("A");
        ExamPaperSubmitVM submit = new ExamPaperSubmitVM();
        submit.setId(101);
        submit.setTaskId(8);
        submit.setDoTime(12);
        submit.setAnswerItems(Arrays.asList(item));
        return submit;
    }

    private User user() {
        User user = new User();
        user.setId(7);
        user.setClassId(2);
        return user;
    }
}
