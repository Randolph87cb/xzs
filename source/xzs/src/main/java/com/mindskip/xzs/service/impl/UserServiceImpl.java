package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.other.KeyValue;
import com.mindskip.xzs.domain.other.ClassRankingItem;
import com.mindskip.xzs.exception.BusinessException;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.event.OnRegistrationCompleteEvent;
import com.mindskip.xzs.repository.UserMapper;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.viewmodel.admin.user.UserPageRequestVM;
import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Comparator;
import java.util.List;
import java.util.Map;


@Service
public class UserServiceImpl extends BaseServiceImpl<User> implements UserService {

    private final UserMapper userMapper;
    private final ApplicationEventPublisher eventPublisher;

    @Autowired
    public UserServiceImpl(UserMapper userMapper, ApplicationEventPublisher eventPublisher) {
        super(userMapper);
        this.userMapper = userMapper;
        this.eventPublisher = eventPublisher;
    }


    @Override
    public List<User> getUsers() {
        return userMapper.getAllUser();
    }

    @Override
    public User getUserById(Integer id) {
        return userMapper.getUserById(id);
    }

    @Override
    public User getUserByUserName(String username) {
        return userMapper.getUserByUserName(username);
    }

    @Override
    public int insertByFilter(User record) {
        return super.insertByFilter(record);
    }

    @Override
    public int updateByIdFilter(User record) {
        return super.updateByIdFilter(record);
    }

    @Override
    public int updateById(User record) {
        return super.updateById(record);
    }

    @Override
    public User getUserByUserNamePwd(String username, String pwd) {
        return userMapper.getUserByUserNamePwd(username, pwd);
    }

    @Override
    public User getUserByUuid(String uuid) {
        return userMapper.getUserByUuid(uuid);
    }

    @Override
    public List<User> userPageList(String name, Integer pageIndex, Integer pageSize) {
        Map<String, Object> map = new HashMap<>(3);
        map.put("name", name);
        map.put("offset", ((int) pageIndex) * pageSize);
        map.put("limit", pageSize);
        return userMapper.userPageList(map);
    }

    @Override
    public Integer userPageCount(String name) {
        Map<String, Object> map = new HashMap<>(1);
        map.put("name", name);
        return userMapper.userPageCount(map);
    }


    @Override
    public PageInfo<User> userPage(UserPageRequestVM requestVM) {
        return PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc").doSelectPageInfo(() ->
                userMapper.userPage(requestVM)
        );
    }


    @Override
    public void insertUser(User user) {
        userMapper.insertSelective(user);
        eventPublisher.publishEvent(new OnRegistrationCompleteEvent(user));
    }

    @Override
    @Transactional(rollbackFor = BusinessException.class)
    public void insertUsers(List<User> users) {
        userMapper.insertUsers(users);
        throw new BusinessException("test BusinessException roll back");
    }

    @Override
    public void updateUser(User user) {
        userMapper.updateUser(user);
    }

    @Override
    public void updateUsersAge(Integer age, List<Integer> ids) {
        Map<String, Object> map = new HashMap<>(2);
        map.put("idslist", ids);
        map.put("age", age);
        userMapper.updateUsersAge(map);
    }

    @Override
    public void deleteUserByIds(List<Integer> ids) {
        userMapper.deleteUsersByIds(ids);
    }

    @Override
    public Integer selectAllCount() {
        return userMapper.selectAllCount();
    }

    @Override
    public List<KeyValue> selectByUserName(String userName) {
        return userMapper.selectByUserName(userName);
    }

    @Override
    public List<KeyValue> selectStudentByUserNameInClasses(String userName, List<Integer> classIds) {
        return userMapper.selectStudentByUserNameInClasses(userName, classIds);
    }

    @Override
    public List<User> selectByIds(List<Integer> ids) {
        return userMapper.selectByIds(ids);
    }

    @Override
    public User selectByWxOpenId(String wxOpenId) {
        return userMapper.selectByWxOpenId(wxOpenId);
    }

    @Override
    public int updateTargetSubjectId(Integer id, Integer targetSubjectId) {
        return userMapper.updateTargetSubjectId(id, targetSubjectId);
    }

    @Override
    public List<ClassRankingItem> classRanking(Integer classId) {
        List<ClassRankingItem> items = userMapper.selectClassRankingBase(classId);
        items.forEach(this::fillRankingScore);
        items.sort(classRankingComparator());
        for (int i = 0; i < items.size(); i++) {
            items.get(i).setRank(i + 1);
        }
        return items;
    }

    private void fillRankingScore(ClassRankingItem item) {
        item.setPaperCount(defaultInt(item.getPaperCount()));
        item.setQuestionCount(defaultInt(item.getQuestionCount()));
        item.setCorrectCount(defaultInt(item.getCorrectCount()));
        item.setCorrectionCount(defaultInt(item.getCorrectionCount()));
        item.setResubmitCount(defaultInt(item.getResubmitCount()));

        BigDecimal accuracyRate = item.getQuestionCount() == 0
                ? BigDecimal.ZERO
                : BigDecimal.valueOf(item.getCorrectCount())
                .divide(BigDecimal.valueOf(item.getQuestionCount()), 4, RoundingMode.HALF_UP);
        item.setAccuracyRate(accuracyRate);

        double score = accuracyRate.doubleValue() * 100
                + Math.log(item.getQuestionCount() + 1D) * 8
                + item.getCorrectionCount() * 2D
                - item.getResubmitCount();
        item.setScore(BigDecimal.valueOf(score).setScale(2, RoundingMode.HALF_UP));
    }

    private Comparator<ClassRankingItem> classRankingComparator() {
        return (left, right) -> {
            int result = compareBigDecimalDesc(left.getScore(), right.getScore());
            if (result != 0) {
                return result;
            }
            result = compareBigDecimalDesc(left.getAccuracyRate(), right.getAccuracyRate());
            if (result != 0) {
                return result;
            }
            result = compareIntegerDesc(left.getQuestionCount(), right.getQuestionCount());
            if (result != 0) {
                return result;
            }
            result = compareDateDescNullLast(left.getLastSubmitTime(), right.getLastSubmitTime());
            if (result != 0) {
                return result;
            }
            return compareIntegerAsc(left.getUserId(), right.getUserId());
        };
    }

    private Integer defaultInt(Integer value) {
        return value == null ? 0 : value;
    }

    private int compareBigDecimalDesc(BigDecimal left, BigDecimal right) {
        if (left == null && right == null) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return right.compareTo(left);
    }

    private int compareIntegerDesc(Integer left, Integer right) {
        if (left == null && right == null) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return right.compareTo(left);
    }

    private int compareIntegerAsc(Integer left, Integer right) {
        if (left == null && right == null) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return left.compareTo(right);
    }

    private int compareDateDescNullLast(java.util.Date left, java.util.Date right) {
        if (left == null && right == null) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return right.compareTo(left);
    }
}
