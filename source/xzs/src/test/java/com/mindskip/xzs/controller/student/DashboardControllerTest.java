package com.mindskip.xzs.controller.student;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.other.ClassRankingItem;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.TaskExamCustomerAnswerService;
import com.mindskip.xzs.service.TaskExamService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.viewmodel.student.dashboard.ClassRankingVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class DashboardControllerTest {

    private UserService userService;
    private DashboardController controller;
    private WebContext webContext;

    @Before
    public void setUp() {
        userService = mock(UserService.class);
        controller = new DashboardController(
                userService,
                mock(ExamPaperService.class),
                mock(QuestionService.class),
                mock(TaskExamService.class),
                mock(TaskExamCustomerAnswerService.class),
                mock(TextContentService.class));
        webContext = mock(WebContext.class);
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void classRankingReturnsEmptyListWhenCurrentStudentHasNoClass() {
        User user = new User();
        user.setId(7);
        when(webContext.getCurrentUser()).thenReturn(user);

        RestResponse<List<ClassRankingVM>> response = controller.classRanking();

        assertEquals(1, response.getCode());
        assertEquals(0, response.getResponse().size());
        verify(userService, never()).classRanking(null);
    }

    @Test
    public void classRankingReturnsOnlyCurrentStudentsClassRanking() {
        User user = new User();
        user.setId(7);
        user.setClassId(5);
        when(webContext.getCurrentUser()).thenReturn(user);
        when(userService.classRanking(5)).thenReturn(Collections.singletonList(rankingItem()));

        RestResponse<List<ClassRankingVM>> response = controller.classRanking();

        assertEquals(1, response.getCode());
        assertEquals(1, response.getResponse().size());
        assertEquals(Integer.valueOf(11), response.getResponse().get(0).getUserId());
        assertEquals("Nick", response.getResponse().get(0).getNickName());
        assertEquals(new BigDecimal("0.7500"), response.getResponse().get(0).getAccuracyRate());
        assertEquals(DateTimeUtil.dateFormat(new Date(0)), response.getResponse().get(0).getLastSubmitTime());
        verify(userService).classRanking(5);
    }

    private ClassRankingItem rankingItem() {
        ClassRankingItem item = new ClassRankingItem();
        item.setUserId(11);
        item.setUserName("student");
        item.setRealName("Real");
        item.setNickName("Nick");
        item.setRank(1);
        item.setPaperCount(2);
        item.setQuestionCount(8);
        item.setCorrectCount(6);
        item.setAccuracyRate(new BigDecimal("0.7500"));
        item.setCorrectionCount(3);
        item.setResubmitCount(1);
        item.setLastSubmitTime(new Date(0));
        item.setScore(new BigDecimal("97.58"));
        return item;
    }
}
