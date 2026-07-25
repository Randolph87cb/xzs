package com.mindskip.xzs.controller.student;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.ExamPaper;
import com.mindskip.xzs.domain.Subject;
import com.mindskip.xzs.service.ExamPaperAnswerService;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperBootstrapRequestVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperBootstrapResponseVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperPageVM;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class ExamPaperControllerTest {

    private ExamPaperService examPaperService;
    private SubjectService subjectService;
    private ExamPaperController controller;

    @Before
    public void setUp() {
        examPaperService = mock(ExamPaperService.class);
        subjectService = mock(SubjectService.class);
        controller = new ExamPaperController(
                examPaperService,
                mock(ExamPaperAnswerService.class),
                subjectService,
                mock(ApplicationEventPublisher.class));
    }

    @Test
    public void bootstrapUsesFirstSubjectAndReturnsItsPage() {
        when(subjectService.allSubject()).thenReturn(Arrays.asList(
                subject(2, "GESP 2级"),
                subject(1, "GESP 1级")));
        ExamPaper paper = new ExamPaper();
        paper.setId(31);
        paper.setName("paper");
        paper.setCreateTime(new Date(0));
        when(examPaperService.studentPage(any())).thenReturn(new PageInfo<>(Collections.singletonList(paper)));

        RestResponse<ExamPaperBootstrapResponseVM> response = controller.bootstrap(request());

        assertEquals(1, response.getCode());
        assertEquals("2", response.getResponse().getSubjects().get(0).getId());
        assertEquals("GESP 2级", response.getResponse().getSubjects().get(0).getName());
        assertEquals(Integer.valueOf(2), response.getResponse().getActiveSubjectId());
        assertEquals(Integer.valueOf(31), response.getResponse().getPage().getList().get(0).getId());
        ArgumentCaptor<ExamPaperPageVM> captor = ArgumentCaptor.forClass(ExamPaperPageVM.class);
        verify(examPaperService).studentPage(captor.capture());
        assertEquals(Integer.valueOf(2), captor.getValue().getSubjectId());
        assertEquals(Integer.valueOf(1), captor.getValue().getPaperType());
        assertEquals(Integer.valueOf(3), captor.getValue().getPageIndex());
        assertEquals(Integer.valueOf(20), captor.getValue().getPageSize());
    }

    @Test
    public void bootstrapReturnsSafeEmptyPageWhenNoSubjectsExist() {
        when(subjectService.allSubject()).thenReturn(Collections.emptyList());

        RestResponse<ExamPaperBootstrapResponseVM> response = controller.bootstrap(request());

        assertEquals(1, response.getCode());
        assertEquals(0, response.getResponse().getSubjects().size());
        assertNull(response.getResponse().getActiveSubjectId());
        assertEquals(0, response.getResponse().getPage().getList().size());
        assertEquals(0L, response.getResponse().getPage().getTotal());
        assertEquals(3, response.getResponse().getPage().getPageNum());
        assertEquals(20, response.getResponse().getPage().getPageSize());
        verify(examPaperService, never()).studentPage(any());
    }

    private ExamPaperBootstrapRequestVM request() {
        ExamPaperBootstrapRequestVM request = new ExamPaperBootstrapRequestVM();
        request.setPaperType(1);
        request.setPageIndex(3);
        request.setPageSize(20);
        return request;
    }

    private Subject subject(Integer id, String name) {
        Subject subject = new Subject();
        subject.setId(id);
        subject.setName(name);
        return subject;
    }
}
