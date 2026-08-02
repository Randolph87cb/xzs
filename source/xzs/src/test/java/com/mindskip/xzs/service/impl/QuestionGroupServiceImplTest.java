package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.QuestionGroup;
import com.mindskip.xzs.domain.Subject;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.repository.QuestionGroupMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupEditRequestVM;
import org.junit.Before;
import org.junit.Test;
import java.util.Arrays;
import java.util.Collections;
import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class QuestionGroupServiceImplTest {
    private QuestionGroupMapper groupMapper;
    private QuestionMapper questionMapper;
    private QuestionService questionService;
    private TextContentService textContentService;
    private SubjectService subjectService;
    private QuestionGroupServiceImpl service;

    @Before
    public void setUp() {
        groupMapper = mock(QuestionGroupMapper.class);
        questionMapper = mock(QuestionMapper.class);
        questionService = mock(QuestionService.class);
        textContentService = mock(TextContentService.class);
        subjectService = mock(SubjectService.class);
        service = new QuestionGroupServiceImpl(groupMapper, questionMapper, questionService, textContentService, subjectService);
        when(subjectService.selectById(9)).thenReturn(new Subject());
        when(subjectService.levelBySubjectId(9)).thenReturn(9);
    }

    @Test
    public void saveReplacesAssignmentsInOneValidatedGroup() {
        QuestionGroup group = group();
        when(groupMapper.selectByPrimaryKey(8)).thenReturn(group);
        when(textContentService.selectById(80)).thenReturn(new TextContent("{\"titleContent\":\"old\"}", null));
        Question child = question(100, 9, 8);
        when(questionMapper.selectByPrimaryKey(100)).thenReturn(child);
        when(questionService.updateFullQuestionFromGroup(
                org.mockito.ArgumentMatchers.any(QuestionEditRequestVM.class),
                org.mockito.ArgumentMatchers.eq(8))).thenReturn(child);

        QuestionGroup result = service.save(request(Arrays.asList(item(100, 9, 1))), 1);

        assertEquals(Integer.valueOf(8), result.getId());
        verify(questionMapper).clearQuestionGroupAssignments(8);
        verify(questionMapper).updateQuestionGroupAssignment(100, 8, 1);
        verify(questionService).updateFullQuestionFromGroup(
                org.mockito.ArgumentMatchers.any(QuestionEditRequestVM.class),
                org.mockito.ArgumentMatchers.eq(8));
    }

    @Test(expected = IllegalArgumentException.class)
    public void activeGroupCannotBeEmpty() {
        service.save(request(Collections.emptyList()), 1);
    }

    @Test(expected = IllegalArgumentException.class)
    public void childSubjectMustMatchParent() {
        service.save(request(Arrays.asList(item(100, 10, 1))), 1);
    }

    @Test(expected = IllegalArgumentException.class)
    public void groupItemOrderMustBeUnique() {
        service.save(request(Arrays.asList(item(null, 9, 1), item(null, 9, 1))), 1);
    }

    @Test(expected = IllegalArgumentException.class)
    public void groupItemOrderMustBeContinuous() {
        service.save(request(Arrays.asList(item(null, 9, 1), item(null, 9, 3))), 1);
    }

    private QuestionGroupEditRequestVM request(java.util.List<QuestionEditRequestVM> items) {
        QuestionGroupEditRequestVM vm = new QuestionGroupEditRequestVM();
        vm.setId(8); vm.setGroupType(1); vm.setSubjectId(9); vm.setDifficult(1);
        vm.setKnowledgePoint("CSP-J/程序阅读"); vm.setTitle("shared"); vm.setStatus(1); vm.setQuestionItems(items);
        return vm;
    }

    private QuestionEditRequestVM item(Integer id, int subjectId, int order) {
        QuestionEditRequestVM vm = new QuestionEditRequestVM();
        vm.setId(id); vm.setSubjectId(subjectId); vm.setGroupItemOrder(order);
        return vm;
    }

    private QuestionGroup group() {
        QuestionGroup group = new QuestionGroup();
        group.setId(8); group.setInfoTextContentId(80); group.setDeleted(false);
        return group;
    }

    private Question question(int id, int subjectId, int groupId) {
        Question q = new Question(); q.setId(id); q.setSubjectId(subjectId); q.setQuestionGroupId(groupId); q.setDeleted(false); return q;
    }
}
