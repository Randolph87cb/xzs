package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.other.ClassRankingItem;
import com.mindskip.xzs.repository.UserMapper;
import org.junit.Before;
import org.junit.Test;
import org.springframework.context.ApplicationEventPublisher;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Date;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class UserServiceImplTest {

    private UserMapper userMapper;
    private UserServiceImpl userService;

    @Before
    public void setUp() {
        userMapper = mock(UserMapper.class);
        userService = new UserServiceImpl(userMapper, mock(ApplicationEventPublisher.class));
    }

    @Test
    public void classRankingComputesAccuracyScoreAndRankFromAggregatedStats() {
        ClassRankingItem firstByAccuracy = item(1, "first", 2, 10, 9, 1, 0, new Date(3000));
        ClassRankingItem highVolume = item(2, "second", 3, 20, 10, 0, 0, new Date(2000));
        ClassRankingItem otherClassShouldNotAppear = item(3, "other", 1, 5, 5, 0, 0, new Date(1000));
        when(userMapper.selectClassRankingBase(8)).thenReturn(Arrays.asList(highVolume, firstByAccuracy));
        when(userMapper.selectClassRankingBase(9)).thenReturn(Arrays.asList(otherClassShouldNotAppear));

        List<ClassRankingItem> ranking = userService.classRanking(8);

        assertEquals(2, ranking.size());
        assertEquals(Integer.valueOf(1), ranking.get(0).getUserId());
        assertEquals(Integer.valueOf(1), ranking.get(0).getRank());
        assertEquals(Integer.valueOf(2), ranking.get(0).getPaperCount());
        assertEquals(Integer.valueOf(10), ranking.get(0).getQuestionCount());
        assertEquals(Integer.valueOf(9), ranking.get(0).getCorrectCount());
        assertEquals(new BigDecimal("0.9000"), ranking.get(0).getAccuracyRate());
        assertEquals(Integer.valueOf(1), ranking.get(0).getCorrectionCount());
        assertEquals(Integer.valueOf(0), ranking.get(0).getResubmitCount());

        assertEquals(Integer.valueOf(2), ranking.get(1).getUserId());
        assertEquals(Integer.valueOf(2), ranking.get(1).getRank());
        assertEquals(new BigDecimal("0.5000"), ranking.get(1).getAccuracyRate());
    }

    private ClassRankingItem item(Integer userId, String userName, Integer paperCount, Integer questionCount,
                                  Integer correctCount, Integer correctionCount, Integer resubmitCount,
                                  Date lastSubmitTime) {
        ClassRankingItem item = new ClassRankingItem();
        item.setUserId(userId);
        item.setUserName(userName);
        item.setRealName(userName);
        item.setNickName(userName + " nick");
        item.setPaperCount(paperCount);
        item.setQuestionCount(questionCount);
        item.setCorrectCount(correctCount);
        item.setCorrectionCount(correctionCount);
        item.setResubmitCount(resubmitCount);
        item.setLastSubmitTime(lastSubmitTime);
        return item;
    }
}
